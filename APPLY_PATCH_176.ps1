$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\screens\statement_preview_dialog.dart")) {
  Write-Host "lkgroup_app 프로젝트 최상위에 압축을 풀고 실행하세요." -ForegroundColor Red
  exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 ".\PATCH176_apply.py"
} else {
  python ".\PATCH176_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch176 Dart/Edge 적용 완료." -ForegroundColor Green
Write-Host "다음 순서:"
Write-Host "1) flutter analyze"
Write-Host "2) Supabase SQL Editor에서 PATCH176_extra_cost_discount.sql 전체 실행"
Write-Host "3) npx supabase functions deploy export-shipment-excel"
Write-Host "4) flutter run"
