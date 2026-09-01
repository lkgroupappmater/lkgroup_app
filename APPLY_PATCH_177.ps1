$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\services\freight_service.dart")) {
  Write-Host "lkgroup_app 프로젝트 최상위에 압축을 풀고 실행하세요." -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH177_apply.py" }
else { python ".\PATCH177_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "Patch177 적용 완료." -ForegroundColor Green
Write-Host "1) flutter analyze"
Write-Host "2) PATCH177_name_matching_receipt_discount.sql 전체 실행"
Write-Host "3) npx supabase functions deploy export-shipment-excel"
Write-Host "4) flutter run"
