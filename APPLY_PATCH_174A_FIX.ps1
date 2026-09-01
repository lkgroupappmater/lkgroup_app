$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\screens")) {
  Write-Host "lkgroup_app 프로젝트 최상위에서 실행하세요." -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH174A_FIX_apply.py" }
else { python ".\PATCH174A_FIX_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch174A FIX 적용 완료." -ForegroundColor Green
Write-Host "이제 flutter analyze 실행하세요."
