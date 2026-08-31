$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\services\excel_import_service.dart")) {
  Write-Host "이 파일들을 lkgroup_app 프로젝트 최상위 폴더에 풀고 실행하세요." -ForegroundColor Red
  exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 ".\PATCH167B_apply.py"
} else {
  python ".\PATCH167B_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Dart 수정 완료." -ForegroundColor Green
Write-Host "1) flutter analyze"
Write-Host "2) Supabase SQL Editor에서 PATCH167B_phone_matches.sql 실행"
Write-Host "3) 같은 V08 Excel 재업로드"
