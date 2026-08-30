$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch127d: Excel sheet6 XML 복구 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$tsPath = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $tsPath)) { throw "파일 없음: $tsPath" }

Copy-Item $tsPath "$tsPath.bak_before_patch127d" -Force

$ts = Get-Content $tsPath -Raw -Encoding UTF8

$old = "    refreshReceiptSheetCaches(files, enrichedShipments);"
$new = "    // Patch127d: 기존 명세서 수식 셀 cached value 직접 수정은 Excel XML 손상 가능성이 있어 비활성화.`r`n    // 명세서 동적 연결은 다음 단계에서 안전한 방식으로 처리합니다."

if (-not $ts.Contains($old)) {
    throw "Patch127d: refreshReceiptSheetCaches 호출을 찾지 못했습니다."
}

$ts = $ts.Replace($old, $new)
Set-Content $tsPath $ts -Encoding UTF8

Write-Host "[OK] sheet6 XML 손상 원인 호출 비활성화 완료" -ForegroundColor Green
Write-Host ""
Write-Host "다음:" -ForegroundColor Cyan
Write-Host "  npx supabase functions deploy export-shipment-excel"
