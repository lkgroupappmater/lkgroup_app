$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\services\excel_import_service.dart")) {
    Write-Host "ERROR: Run from lkgroup_app project root." -ForegroundColor Red
    exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 ".\PATCH179_apply.py"
} else {
    python ".\PATCH179_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch179 applied." -ForegroundColor Green
Write-Host "NEXT 1: flutter analyze"
Write-Host "NEXT 2: flutter run"
Write-Host "NEXT 3: upload V00 BASE again"
