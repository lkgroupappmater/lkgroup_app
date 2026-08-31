$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".\supabase\functions\export-shipment-excel\index.ts")) {
  Write-Host "lkgroup_app 프로젝트 최상위에 압축을 풀고 실행하세요." -ForegroundColor Red
  exit 1
}
if (Get-Command py -ErrorAction SilentlyContinue) { py -3 ".\PATCH173_apply.py" }
else { python ".\PATCH173_apply.py" }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Patch173 적용 완료." -ForegroundColor Green
Write-Host "1) flutter analyze"
Write-Host "2) npx supabase functions deploy export-shipment-excel"
Write-Host "3) 같은 V08 Excel 다시 다운로드"
