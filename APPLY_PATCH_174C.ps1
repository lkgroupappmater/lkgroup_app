$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\screens\excel_export_screen.dart")) {
  Write-Host "lkgroup_app 프로젝트 최상위에 압축을 풀고 실행하세요." -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH174C_apply.py" }
else { python ".\PATCH174C_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch174C 적용 완료." -ForegroundColor Green
Write-Host "1) flutter analyze"
Write-Host "2) Supabase SQL Editor에서 PATCH174C_fast_recalculate.sql 전체 실행"
Write-Host "3) flutter run"
