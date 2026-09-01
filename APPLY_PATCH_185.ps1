$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\screens\statement_preview_dialog.dart")) {
    Write-Host "ERROR: Run from lkgroup_app project root." -ForegroundColor Red
    exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 ".\PATCH185_apply.py"
} else {
    python ".\PATCH185_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch185 VERIFIED and complete." -ForegroundColor Green
Write-Host "NEXT 1: flutter analyze"
Write-Host "NEXT 2: npx supabase functions deploy export-shipment-excel"
Write-Host "NEXT 3: flutter run"
