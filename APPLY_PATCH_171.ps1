$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\screens\statement_preview_dialog.dart")) {
  Write-Host "lkgroup_app 프로젝트 최상위에 압축을 풀고 실행하세요." -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH171_apply.py" }
else { python ".\PATCH171_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Patch171 Dart 완료 -> flutter analyze -> SQL Editor에서 PATCH171_delivery_token_match.sql 실행" -ForegroundColor Green
