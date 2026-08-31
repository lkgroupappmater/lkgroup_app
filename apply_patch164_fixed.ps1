param(
    [string]$ProjectRoot = "C:\Users\ssapd\StudioProjects\lkgroup_app"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectRoot

$ExpectedCommit = "11f10992339f498f7ac207d351c62e607e62431d"
$ExpectedCustomerSha = "58bd59d8d02856a9285f482c7214097eef0c61c8"
$ExpectedExporterSha = "1e0a041c50e3629d606d94c8941ad3573d855cd6"

git fetch origin master
$OriginMaster = (git rev-parse origin/master).Trim()
$Head = (git rev-parse HEAD).Trim()

if ($OriginMaster -ne $ExpectedCommit) {
    throw "origin/master changed. Expected $ExpectedCommit but found $OriginMaster. No files changed."
}
if ($Head -ne $ExpectedCommit) {
    throw "Local HEAD changed. Expected $ExpectedCommit but found $Head. No files changed."
}

$customerPath = "lib/services/customer_benefit_service.dart"
$exporterPath = "supabase/functions/export-shipment-excel/index.ts"

$customerBlob = (git hash-object $customerPath).Trim()
$exporterBlob = (git hash-object $exporterPath).Trim()

if ($customerBlob -ne $ExpectedCustomerSha) {
    throw "$customerPath differs from verified master. No files changed."
}
if ($exporterBlob -ne $ExpectedExporterSha) {
    throw "$exporterPath differs from verified master. No files changed."
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 1) customer_benefit_service.dart: append paidBy to statement delivery text.
$customer = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot $customerPath), [System.Text.Encoding]::UTF8)

$oldCustomer = @"
      tel,
      localCompany,
      destinationAddress,
    ].where((e) => e.trim().isNotEmpty).join(', ');
"@
$newCustomer = @"
      tel,
      localCompany,
      destinationAddress,
      paidBy,
    ].where((e) => e.trim().isNotEmpty).join(', ');
"@

if (-not $customer.Contains($oldCustomer)) {
    throw "CustomerBenefitService target block not found. No files changed."
}
$customerNew = $customer.Replace($oldCustomer, $newCustomer)

# 2) exporter: fix Korea-prepaid detection and include paid_by in exported delivery text.
$exporter = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot $exporterPath), [System.Text.Encoding]::UTF8)

$oldExporterBlock = @"
    const paidBy = String(d?.paid_by ?? '').toLowerCase();
    const type = d ? (String(d.delivery_type ?? '') === 'city' ? 'city' : (paidBy.includes('?쒓뎅') || paidBy.includes('korea') || paidBy.includes('prepaid') ? 'province_prepaid_kr' : 'province')) : '';
    const delivery = d ? [d.source_no ? `(${d.source_no})` : '', d.alternate_name || d.customer_name || name, d.phone_display || d.phone || phone, d.local_company, d.destination_address].filter(Boolean).join(', ') : '';
"@

$newExporterBlock = @"
    const paidBy = String(d?.paid_by ?? '').toLowerCase();
    const koreaMarker =
      paidBy.includes('\uD55C\uAD6D') || paidBy.includes('korea');
    const prepaidMarker =
      paidBy.includes('\uC120\uACB0\uC81C') ||
      paidBy.includes('\uC120\uBD88') ||
      paidBy.includes('prepaid');
    const isKoreaPrepaid = koreaMarker && prepaidMarker;
    const type = d ? (String(d.delivery_type ?? '') === 'city' ? 'city' : (isKoreaPrepaid ? 'province_prepaid_kr' : 'province')) : '';
    const delivery = d ? [d.source_no ? `(${d.source_no})` : '', d.alternate_name || d.customer_name || name, d.phone_display || d.phone || phone, d.local_company, d.destination_address, d.paid_by].filter(Boolean).join(', ') : '';
"@

if (-not $exporter.Contains($oldExporterBlock)) {
    throw "Exporter paidBy target block not found. No files changed."
}
$exporterNew = $exporter.Replace($oldExporterBlock, $newExporterBlock)

$oldSelect = @"
      .select('source_no,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes')
      .eq('route_key', routeKey)
      .eq('active', true);
"@

$newSelect = @"
      .select('source_no,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes,preferred')
      .eq('route_key', routeKey)
      .eq('active', true)
      .order('preferred', { ascending: false })
      .order('source_no', { ascending: true });
"@

if (-not $exporterNew.Contains($oldSelect)) {
    throw "Exporter local-delivery select target block not found. No files changed."
}
$exporterNew = $exporterNew.Replace($oldSelect, $newSelect)

# Only after every validation succeeded, write files.
[System.IO.File]::WriteAllText((Join-Path $ProjectRoot $customerPath), $customerNew, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $ProjectRoot $exporterPath), $exporterNew, $utf8NoBom)

# Copy SQL into project Supabase folder.
$sqlSource = Join-Path $PSScriptRoot "supabase_096_delivery_document_consistency.sql"
$sqlTarget = Join-Path $ProjectRoot "supabase/supabase_096_delivery_document_consistency.sql"
[System.IO.File]::Copy($sqlSource, $sqlTarget, $true)

Write-Host ""
Write-Host "Patch164 FIXED applied successfully."
Write-Host ""
git diff --check
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed. Inspect changes before continuing."
}
git diff -- $customerPath $exporterPath "supabase/supabase_096_delivery_document_consistency.sql"

Write-Host ""
Write-Host "Next:"
Write-Host "1) If 095 SQL was never run, run supabase_095_local_delivery_import_preferred.sql first."
Write-Host "2) Run supabase/supabase_096_delivery_document_consistency.sql in Supabase SQL Editor."
Write-Host "3) npx supabase functions deploy export-shipment-excel"
Write-Host "4) flutter analyze"
