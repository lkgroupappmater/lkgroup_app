$ErrorActionPreference = "Stop"
$path = "supabase/functions/export-shipment-excel/index.ts"
if (!(Test-Path $path)) { throw "파일 없음: $path" }

$text = Get-Content $path -Raw -Encoding UTF8

function Replace-Once([string]$source,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($source,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: anchor 개수=$count" }
  return $source.Replace($old,$new)
}

# 1) DB shipment rows를 source of truth로 사용.
# request shipment_rows는 운임 계산용 참고값일 수 있으므로 Excel 원본 화물/잠금값을 덮지 않게 함.
$old1 = @'
    // Excel 출력은 Flutter가 중앙 FreightService 정산에 사용한 동일 rows를 최우선 사용합니다.
    // Edge Function의 별도 재조회 결과가 일부 필드만 갖는 경우에도 출력 데이터가 빠지지 않습니다.
    const exportShipmentRows =
      requestShipmentRows.length > 0
        ? requestShipmentRows
        : (shipments ?? []) as Record<string, unknown>[];

    const enrichedShipments = assignReceiptNumbers(
      exportShipmentRows,
'@
$new1 = @'
    // Patch161: 실제 Excel 화물행은 DB의 현재 shipments를 source of truth로 사용합니다.
    // 특히 잠금 재업로드 변경요청이 pending/rejected인 경우 request payload의
    // incoming Excel 값을 출력에 섞지 않습니다.
    // 중앙 FreightService 정산값은 아래 voyage_settlement_snapshots에서 별도로 사용합니다.
    const exportShipmentRows =
      (shipments ?? []) as Record<string, unknown>[];

    const enrichedShipments = assignReceiptNumbers(
      exportShipmentRows,
'@
$text = Replace-Once $text $old1 $new1 "DB source-of-truth"

# 2) 기타비용 조회 + snapshot 금액 합산
$old2 = @'
    if (settlementSnapshotError) throw settlementSnapshotError;

    const filePrefixes: Record<string, string> = {
'@
$new2 = @'
    if (settlementSnapshotError) throw settlementSnapshotError;

    // Patch161: 영수번호별 기타 비용을 실제 Excel 정산금액에도 반영합니다.
    // 운임 자체는 FreightService snapshot을 그대로 사용하고,
    // 기타비용은 운임 계산 후 별도 가산합니다.
    const { data: receiptExtraCosts, error: receiptExtraCostsError } =
      await admin
        .from('receipt_extra_costs')
        .select('receipt_number,cost_name,amount_usd')
        .eq('route', shipmentRouteLabel)
        .eq('shipment_year', shipmentYear);

    if (receiptExtraCostsError) throw receiptExtraCostsError;

    const voyageDigits = voyage.replace(/[^0-9]/g, '');
    const voyageExtraCosts = (receiptExtraCosts ?? []).filter((row) => {
      // 현재 테이블 select에 voyage를 포함하도록 아래 쿼리에서 보강됩니다.
      const rowVoyage = String((row as Record<string, unknown>).voyage ?? '');
      return rowVoyage.replace(/[^0-9]/g, '') === voyageDigits;
    }) as Record<string, unknown>[];

    const extraByReceipt = new Map<string, number>();
    let extraCostTotalUsd = 0;
    for (const item of voyageExtraCosts) {
      const receipt = String(item.receipt_number ?? '').trim();
      const amount = Number(item.amount_usd ?? 0);
      if (!receipt || !Number.isFinite(amount)) continue;
      extraByReceipt.set(receipt, (extraByReceipt.get(receipt) ?? 0) + amount);
      extraCostTotalUsd += amount;
    }

    const settlementForExcel =
      settlementSnapshot && typeof settlementSnapshot === 'object'
        ? (() => {
            const copy = {
              ...(settlementSnapshot as Record<string, unknown>),
            };
            const rawReceipts = Array.isArray(copy.receipts)
              ? copy.receipts as Record<string, unknown>[]
              : [];
            copy.receipts = rawReceipts.map((receipt) => {
              const receiptNo = String(receipt.receipt_number ?? '').trim();
              const extra = extraByReceipt.get(receiptNo) ?? 0;
              return {
                ...receipt,
                extra_cost_usd: extra,
                net_usd: Number(receipt.net_usd ?? 0) + extra,
              };
            });
            copy.extra_cost_usd = extraCostTotalUsd;
            copy.net_usd = Number(copy.net_usd ?? 0) + extraCostTotalUsd;
            return copy;
          })()
        : settlementSnapshot;

    const filePrefixes: Record<string, string> = {
'@
$text = Replace-Once $text $old2 $new2 "extra-cost settlement"

# select에 voyage 포함
$old3 = ".select('receipt_number,cost_name,amount_usd')"
$new3 = ".select('voyage,receipt_number,cost_name,amount_usd')"
$text = Replace-Once $text $old3 $new3 "extra-cost voyage select"

# 3) Row data 기존 Amount에 기타비용 포함된 settlementForExcel 사용
$old4 = @'
      settlementSnapshot as Record<string, unknown> | null,
      shipmentRouteLabel,
'@
$new4 = @'
      settlementForExcel as Record<string, unknown> | null,
      shipmentRouteLabel,
'@
$text = Replace-Once $text $old4 $new4 "Row data settlement"

Set-Content -Path $path -Value $text -Encoding UTF8

Write-Host ""
Write-Host "Patch161 적용 완료"
Write-Host " - Excel export: DB 현재 화물값 우선 (잠금/거절 incoming 값 혼입 방지)"
Write-Host " - Excel Row data Amount: 영수번호별 기타비용 합산"
Write-Host " - SQL093: pending 잠금 화물 DB 덮어쓰기 보호"
Write-Host ""
Write-Host "다음:"
Write-Host "  1) flutter analyze"
Write-Host "  2) Supabase SQL Editor: supabase_093_reupload_reject_guard.sql"
Write-Host "  3) supabase functions deploy export-shipment-excel"
