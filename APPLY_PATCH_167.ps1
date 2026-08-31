$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
Write-Host "Patch167 - delivery link / receipt order / zone / badge" -ForegroundColor Cyan

if (-not (Test-Path ".\lib\services\excel_import_service.dart")) {
    Write-Host "Run this script from the lkgroup_app project root." -ForegroundColor Red
    exit 1
}

$py = Get-Command py -ErrorAction SilentlyContinue
if ($py) {
    py -3 ".\PATCH167_apply.py"
} else {
    python ".\PATCH167_apply.py"
}

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch applied. Next run:" -ForegroundColor Green
Write-Host "  flutter analyze"
Write-Host ""
Write-Host "Then re-upload the same V08 BASE Excel once for verification."
