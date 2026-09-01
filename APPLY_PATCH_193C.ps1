$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH193C_apply.py" } else { python ".\PATCH193C_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "Patch193C applied and verified." -ForegroundColor Green
Write-Host "NEXT: flutter analyze"
