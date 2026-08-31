$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\services\customer_benefit_service.dart")) {
  Write-Host "lkgroup_app 프로젝트 최상위에서 실행하세요." -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH170_apply.py" }
else { python ".\PATCH170_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "Patch170 적용 완료." -ForegroundColor Green
Write-Host "flutter analyze"
