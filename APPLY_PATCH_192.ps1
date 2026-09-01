$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\screens\customer_list_management_screen.dart")) { Write-Host "ERROR: project root required" -ForegroundColor Red; exit 1 }
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH192_apply.py" } else { python ".\PATCH192_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "Patch192 applied and verified." -ForegroundColor Green
Write-Host "NEXT: flutter analyze"
