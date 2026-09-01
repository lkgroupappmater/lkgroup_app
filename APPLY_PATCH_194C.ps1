$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\lib\screens\change_approval_screen.dart")) {
  Write-Host "ERROR: project root required" -ForegroundColor Red
  exit 1
}

if (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 ".\PATCH194C_apply.py"
} else {
  python ".\PATCH194C_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch194C applied and verified." -ForegroundColor Green
Write-Host "NEXT: flutter analyze"
