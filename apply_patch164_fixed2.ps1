param([string]$ProjectRoot = "C:\Users\ssapd\StudioProjects\lkgroup_app")
$ErrorActionPreference = "Stop"
Set-Location $ProjectRoot

$ExpectedCommit = "11f10992339f498f7ac207d351c62e607e62431d"
$ExpectedCustomerSha = "58bd59d8d02856a9285f482c7214097eef0c61c8"
$ExpectedExporterSha = "1e0a041c50e3629d606d94c8941ad3573d855cd6"

git fetch origin master
if ((git rev-parse origin/master).Trim() -ne $ExpectedCommit) { throw "origin/master changed. No files changed." }
if ((git rev-parse HEAD).Trim() -ne $ExpectedCommit) { throw "Local HEAD changed. No files changed." }
if ((git hash-object "lib/services/customer_benefit_service.dart").Trim() -ne $ExpectedCustomerSha) { throw "customer_benefit_service.dart changed. No files changed." }
if ((git hash-object "supabase/functions/export-shipment-excel/index.ts").Trim() -ne $ExpectedExporterSha) { throw "exporter changed. No files changed." }

$srcCustomer = Join-Path $PSScriptRoot "files\lib\services\customer_benefit_service.dart"
$dstCustomer = Join-Path $ProjectRoot "lib\services\customer_benefit_service.dart"
$srcSql = Join-Path $PSScriptRoot "files\supabase\supabase_096_delivery_document_consistency.sql"
$dstSql = Join-Path $ProjectRoot "supabase\supabase_096_delivery_document_consistency.sql"

Copy-Item $srcCustomer $dstCustomer -Force
Copy-Item $srcSql $dstSql -Force

node (Join-Path $PSScriptRoot "modify_exporter.js")
if ($LASTEXITCODE -ne 0) { throw "Exporter modification failed." }

git diff --check
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

Write-Host ""
Write-Host "Patch164 FIXED2 applied successfully."
Write-Host ""
git diff -- "lib/services/customer_benefit_service.dart" "supabase/functions/export-shipment-excel/index.ts" "supabase/supabase_096_delivery_document_consistency.sql"
