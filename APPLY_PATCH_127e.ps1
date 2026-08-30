$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch127e: Excel 화물 데이터 소스 통일 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$dartPath = Join-Path $projectRoot "lib\services\excel_export_service.dart"
$tsPath   = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"

if (!(Test-Path $dartPath)) { throw "파일 없음: $dartPath" }
if (!(Test-Path $tsPath))   { throw "파일 없음: $tsPath" }

Copy-Item $dartPath "$dartPath.bak_before_patch127e" -Force
Copy-Item $tsPath "$tsPath.bak_before_patch127e" -Force

# ----------------------------------------------------------------------
# 1) Flutter: FreightService 정산에 실제 사용한 admin_excel_bulk_rows 결과를
#    Edge Function에도 그대로 전달
# ----------------------------------------------------------------------
$dart = Get-Content $dartPath -Raw -Encoding UTF8

if ($dart -notmatch "'shipment_rows': settlementRows") {
    $needle = "        'route_label': batch.routeLabel,"
    if (-not $dart.Contains($needle)) {
        throw "excel_export_service.dart: route_label body 위치를 찾지 못했습니다."
    }
    $dart = $dart.Replace(
        $needle,
        $needle + "`r`n        'shipment_rows': settlementRows,"
    )
    Set-Content $dartPath $dart -Encoding UTF8
    Write-Host "[OK] Flutter -> Edge shipment_rows 전달 추가" -ForegroundColor Green
} else {
    Write-Host "[SKIP] shipment_rows 전달 이미 적용됨" -ForegroundColor Yellow
}

# ----------------------------------------------------------------------
# 2) Edge Function:
#    직접 shipments 재조회 결과보다 Flutter가 정산에 실제 사용한 rows를 우선 사용.
#    이로써 FreightService / Row data / 물품 입고 내역이 동일한 원본 rows를 사용.
# ----------------------------------------------------------------------
$ts = Get-Content $tsPath -Raw -Encoding UTF8

if ($ts -notmatch "requestShipmentRows") {
    $needle = "    const shipmentRouteLabel ="
    $idx = $ts.IndexOf($needle)
    if ($idx -lt 0) {
        throw "index.ts: shipmentRouteLabel 위치를 찾지 못했습니다."
    }

    $insert = @'
    const requestShipmentRows = Array.isArray(body.shipment_rows)
      ? body.shipment_rows
          .filter((row) => row != null && typeof row === 'object' && !Array.isArray(row))
          .map((row) => row as Record<string, unknown>)
      : [];

'@
    $ts = $ts.Insert($idx, $insert)
}

$old = @'
    const enrichedShipments = assignReceiptNumbers(
      (shipments ?? []) as Record<string, unknown>[],
      routeKey,
      String(routeDefinition?.receipt_prefix ?? ''),
    ).map((shipment) => {
'@

$new = @'
    // Excel 출력은 Flutter가 중앙 FreightService 정산에 사용한 동일 rows를 최우선 사용합니다.
    // Edge Function의 별도 재조회 결과가 일부 필드만 갖는 경우에도 출력 데이터가 빠지지 않습니다.
    const exportShipmentRows =
      requestShipmentRows.length > 0
        ? requestShipmentRows
        : (shipments ?? []) as Record<string, unknown>[];

    const enrichedShipments = assignReceiptNumbers(
      exportShipmentRows,
      routeKey,
      String(routeDefinition?.receipt_prefix ?? ''),
    ).map((shipment) => {
'@

if (-not $ts.Contains($old)) {
    $old = $old -replace "`r`n","`n"
    $new = $new -replace "`r`n","`n"
}
if (-not $ts.Contains($old)) {
    throw "index.ts: assignReceiptNumbers 기존 블록을 찾지 못했습니다."
}
$ts = $ts.Replace($old, $new)

Set-Content $tsPath $ts -Encoding UTF8

Write-Host "[OK] Edge Function Excel 데이터 소스 통일 완료" -ForegroundColor Green
Write-Host ""
Write-Host "Patch127e 적용 완료." -ForegroundColor Cyan
Write-Host "다음 순서:" -ForegroundColor Cyan
Write-Host "  flutter analyze"
Write-Host "  npx supabase functions deploy export-shipment-excel"
Write-Host "  flutter run"
