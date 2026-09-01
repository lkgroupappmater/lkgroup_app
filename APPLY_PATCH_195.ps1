$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\screens\quote_request_screen.dart")) {
  Write-Host "ERROR: Run from lkgroup_app project root." -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH195_apply.py" } else { python ".\PATCH195_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "Patch195 applied and verified." -ForegroundColor Green
Write-Host "NEXT: flutter analyze"
