$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\lib\screens\cargo_management_screen.dart")) {
  Write-Host "ERROR: project root required" -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 ".\PATCH194_apply.py"
} else {
  python ".\PATCH194_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "Patch194 Dart applied and verified." -ForegroundColor Green
Write-Host "NEXT: run Patch194_manual_uncertain.sql in Supabase SQL Editor, then flutter analyze"
