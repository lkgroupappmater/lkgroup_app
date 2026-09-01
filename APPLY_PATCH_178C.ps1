$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\services\excel_import_service.dart")) {
    Write-Host "ERROR: Run from lkgroup_app project root." -ForegroundColor Red
    exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 ".\PATCH178C_apply.py"
} else {
    python ".\PATCH178C_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch178C applied." -ForegroundColor Green
Write-Host "NEXT: flutter analyze"
Write-Host "Then flutter run and upload V00 again."
