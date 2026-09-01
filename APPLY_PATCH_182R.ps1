$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\services\freight_service.dart")) {
    Write-Host "ERROR: Run from lkgroup_app project root." -ForegroundColor Red
    exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 ".\PATCH182R_apply.py"
} else {
    python ".\PATCH182R_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch182R applied." -ForegroundColor Green
Write-Host "NEXT: flutter analyze"
Write-Host "THEN: flutter run"
