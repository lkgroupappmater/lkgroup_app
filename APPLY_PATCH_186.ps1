$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\screens\statement_preview_dialog.dart")) {
    Write-Host "ERROR: Run from lkgroup_app project root." -ForegroundColor Red
    exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 ".\PATCH186_apply.py"
} else {
    python ".\PATCH186_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch186 applied and verified." -ForegroundColor Green
Write-Host "NEXT: flutter analyze"
