$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\services\excel_import_service.dart")) {
    Write-Host "ERROR: Run this script from the lkgroup_app project root." -ForegroundColor Red
    exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 ".\PATCH178_apply.py"
} else {
    python ".\PATCH178_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch178 applied." -ForegroundColor Green
Write-Host "NEXT 1: flutter analyze"
Write-Host "NEXT 2: Run PATCH178_v00_base_update.sql in Supabase SQL Editor"
Write-Host "NEXT 3: flutter run"
Write-Host "NEXT 4: Upload KR_LA_SEA_2026_V00_SHIPMENTS.xlsx without renaming it"
