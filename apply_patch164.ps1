param(
    [string]$ProjectRoot = "C:\Users\ssapd\StudioProjects\lkgroup_app"
)

$ErrorActionPreference = "Stop"
$ExpectedBase = "11f10992339f498f7ac207d351c62e607e62431d"
$PatchFile = Join-Path $PSScriptRoot "Patch164.patch"

Set-Location $ProjectRoot

git fetch origin master
$OriginMaster = (git rev-parse origin/master).Trim()
$Head = (git rev-parse HEAD).Trim()

if ($OriginMaster -ne $ExpectedBase) {
    throw "origin/master changed. Expected $ExpectedBase but found $OriginMaster. Do not force-apply this patch."
}

if ($Head -ne $ExpectedBase) {
    throw "Local HEAD is not the verified base commit. Expected $ExpectedBase but found $Head."
}

git apply --check $PatchFile
if ($LASTEXITCODE -ne 0) {
    throw "git apply --check failed. No files were changed."
}

git apply --whitespace=nowarn $PatchFile
if ($LASTEXITCODE -ne 0) {
    throw "git apply failed."
}

Write-Host ""
Write-Host "Patch164 applied successfully."
Write-Host "Next:"
Write-Host "1) Run supabase\supabase_096_delivery_document_consistency.sql in Supabase SQL Editor"
Write-Host "2) npx supabase functions deploy export-shipment-excel"
Write-Host "3) flutter analyze"
