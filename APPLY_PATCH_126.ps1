$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Target = Join-Path $Root "supabase\functions\export-shipment-excel\index.ts"

if (!(Test-Path $Target)) {
  throw "대상 Edge Function 파일을 찾을 수 없습니다: $Target"
}

Copy-Item $Target "$Target.bak_before_patch126" -Force
$text = Get-Content $Target -Raw -Encoding UTF8

$helperMarker = "function appendRowDataSettlementBlock("
if ($text -notmatch [regex]::Escape($helperMarker)) {
$helper = @'

function appendRowDataSettlementBlock(
  files: Record<string, Uint8Array>,
  snapshot: Record<string, unknown> | null,
  routeKey: string,
  shipmentYear: number,
  voyage: string,
): void {
  if (!snapshot) return;

  const path = workbookSheetPath(files, 'Row data');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);
  const sheetDataClose = xml.lastIndexOf('</sheetData>');
  if (sheetDataClose < 0) return;

  const rowNumbers = [...xml.matchAll(/<row\b[^>]*r="(\d+)"/g)]
    .map((m) => Number(m[1]))
    .filter((n) => Number.isFinite(n));
  let row = (rowNumbers.length ? Math.max(...rowNumbers) : 0) + 2;

  const rows: string[] = [];
  const addRow = (values: Array<string | number | null>) => {
    const cells = values.map((value, index) => {
      const col = String.fromCharCode(65 + index);
      const ref = `${col}${row}`;
      if (value == null || value === '') return blankCell(ref, '');
      return typeof value === 'number'
        ? numericCell(ref, '', value)
        : inlineCell(ref, '', value);
    }).join('');
    rows.push(`<row r="${row}">${cells}</row>`);
    row += 1;
  };

  const receiptsRaw = snapshot.receipts;
  const receipts = Array.isArray(receiptsRaw)
    ? receiptsRaw as Record<string, unknown>[]
    : [];

  const discountRaw = snapshot.discount_by_group;
  const discountByGroup =
    discountRaw && typeof discountRaw === 'object' && !Array.isArray(discountRaw)
      ? discountRaw as Record<string, unknown>
      : {};

  addRow(['SYSTEM SETTLEMENT / 시스템 정산']);
  addRow([
    `${shipmentYear} ${voyage.endsWith('항차') ? voyage : `${voyage}항차`}`,
    routeKey,
  ]);
  addRow([
    'Receipt',
    'Customer',
    'Qty',
    'Gross USD',
    'Discount USD',
    'Amount USD',
  ]);

  for (const receipt of receipts) {
    addRow([
      String(receipt.receipt_number ?? ''),
      String(receipt.customer_name ?? ''),
      Number(receipt.total_quantity ?? 0),
      Number(receipt.gross_usd ?? 0),
      Number(receipt.discount_usd ?? 0),
      Number(receipt.net_usd ?? 0),
    ]);
  }

  row += 1;
  addRow(['Discount Group', 'Discount Amount USD']);
  for (const [group, amount] of Object.entries(discountByGroup)) {
    addRow([group, Number(amount ?? 0)]);
  }

  row += 1;
  addRow(['Total', Number(snapshot.total_quantity ?? 0)]);
  addRow(['Gross', Number(snapshot.gross_usd ?? 0)]);
  addRow(['Discount', Number(snapshot.discount_usd ?? 0)]);
  addRow(['Amount', Number(snapshot.net_usd ?? 0)]);
  addRow([
    'Calculated at',
    String(snapshot.calculated_at ?? ''),
  ]);

  xml =
    `${xml.substring(0, sheetDataClose)}${rows.join('')}${xml.substring(sheetDataClose)}`;

  // dimension은 Excel 필수 요소는 아니지만 실제 사용영역을 넓혀 둡니다.
  const finalRow = row - 1;
  if (/<dimension\b[^>]*ref="[^"]+"[^>]*\/>/.test(xml)) {
    xml = xml.replace(
      /<dimension\b([^>]*)ref="([^"]+)"([^>]*)\/>/,
      (_m, before, ref, after) => {
        const start = String(ref).split(':')[0] || 'A1';
        return `<dimension${before}ref="${start}:F${finalRow}"${after}/>`;
      },
    );
  }

  files[path] = strToU8(xml);
}

'@

  $serveNeedle = "Deno.serve(async (req) => {"
  if (!$text.Contains($serveNeedle)) {
    throw "Deno.serve 위치를 찾지 못했습니다."
  }
  $text = $text.Replace($serveNeedle, $helper + $serveNeedle)
}

# snapshot query 삽입
if ($text -notmatch "voyage_settlement_snapshots") {
$queryNeedle = @'
    const exchangeRate = exchangeRateRows?.[0] ?? null;

    const filePrefixes: Record<string, string> = {
'@
$queryInsert = @'
    const exchangeRate = exchangeRateRows?.[0] ?? null;

    // Flutter의 중앙 FreightService가 직전에 저장한 영수번호별 정산 snapshot.
    // Excel에서는 별도 운임 공식을 다시 계산하지 않고 이 값을 그대로 기록합니다.
    const { data: settlementSnapshot, error: settlementSnapshotError } =
      await admin
        .from('voyage_settlement_snapshots')
        .select(
          'total_quantity,gross_usd,discount_usd,net_usd,discount_by_group,receipts,calculated_at',
        )
        .eq('route_key', routeKey)
        .eq('shipment_year', shipmentYear)
        .eq('voyage', voyage)
        .maybeSingle();

    if (settlementSnapshotError) throw settlementSnapshotError;

    const filePrefixes: Record<string, string> = {
'@
  if (!$text.Contains($queryNeedle)) {
    throw "정산 snapshot 조회 삽입 위치를 찾지 못했습니다."
  }
  $text = $text.Replace($queryNeedle, $queryInsert)
}

# Row data 기록 호출 삽입
if ($text -notmatch "appendRowDataSettlementBlock\(\s*files,\s*settlementSnapshot") {
$callNeedle = @'
    if (exchangeRate) {
      updateExchangeRates(files, {
        baseKip: Number(exchangeRate.base_kip ?? 0),
        baseThb: Number(exchangeRate.base_thb ?? 0),
        baseKrw: Number(exchangeRate.base_krw ?? 0),
        kipAdjustment: Number(exchangeRate.kip_adjustment ?? 2000),
        thbAdjustment: Number(exchangeRate.thb_adjustment ?? 1.5),
        krwAdjustment: Number(exchangeRate.krw_adjustment ?? 40),
      });
    }

    // 수식 셀 자체는 보존하고, 오래된 calcChain만 정상적으로 제거합니다.
'@
$callInsert = @'
    if (exchangeRate) {
      updateExchangeRates(files, {
        baseKip: Number(exchangeRate.base_kip ?? 0),
        baseThb: Number(exchangeRate.base_thb ?? 0),
        baseKrw: Number(exchangeRate.base_krw ?? 0),
        kipAdjustment: Number(exchangeRate.kip_adjustment ?? 2000),
        thbAdjustment: Number(exchangeRate.thb_adjustment ?? 1.5),
        krwAdjustment: Number(exchangeRate.krw_adjustment ?? 40),
      });
    }

    // 기존 Row data의 수식/표는 건드리지 않고, 맨 아래에 DB 정산 원본 블록을 추가합니다.
    // 따라서 수백 개 영수증 sheet를 만들지 않아도 영수번호별 실제 금액/할인/총액을
    // Excel 파일 자체에 보관할 수 있습니다.
    appendRowDataSettlementBlock(
      files,
      settlementSnapshot as Record<string, unknown> | null,
      routeKey,
      shipmentYear,
      voyage,
    );

    // 수식 셀 자체는 보존하고, 오래된 calcChain만 정상적으로 제거합니다.
'@
  if (!$text.Contains($callNeedle)) {
    throw "Row data 정산 기록 호출 삽입 위치를 찾지 못했습니다."
  }
  $text = $text.Replace($callNeedle, $callInsert)
}

Set-Content $Target $text -Encoding UTF8

Write-Host "Patch126 적용 완료."
Write-Host ""
Write-Host "중요: Flutter analyze만으로 Edge Function 배포는 되지 않습니다."
Write-Host "다음 실행:"
Write-Host "1) flutter analyze"
Write-Host "2) supabase functions deploy export-shipment-excel"
Write-Host ""
Write-Host "SQL 재실행 없음 (Patch125의 069가 적용되어 있어야 함)."
