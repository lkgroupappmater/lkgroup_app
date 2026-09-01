$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\services\excel_import_service.dart")) {
  Write-Host "lkgroup_app 프로젝트 최상위에 압축을 풀고 실행하세요." -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH175A_apply.py" }
else { python ".\PATCH175A_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "Patch175A Dart 적용 완료." -ForegroundColor Green
Write-Host "1) flutter analyze"
Write-Host "2) Supabase SQL Editor에서 PATCH175A_remark_share_rules.sql 전체 실행"
Write-Host "3) flutter run"
Write-Host "4) 기존 V08은 파일관리에서 재연산 및 Update 실행"
