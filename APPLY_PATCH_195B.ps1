$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\screens\quotation_preview_dialog.dart")) {
  Write-Host "ERROR: Run this from lkgroup_app project root." -ForegroundColor Red
  exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 ".\PATCH195B_apply.py"
} else {
  python ".\PATCH195B_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch195B applied and verified." -ForegroundColor Green
Write-Host "NEXT: flutter analyze"
