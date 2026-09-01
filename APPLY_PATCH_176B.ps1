$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 ".\PATCH176B_apply.py"
} else {
  python ".\PATCH176B_apply.py"
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Patch176B 완료. 이제 flutter analyze 실행하세요." -ForegroundColor Green
