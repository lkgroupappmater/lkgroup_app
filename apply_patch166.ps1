param(
  [string]$ProjectRoot = "C:\Users\ssapd\StudioProjects\lkgroup_app"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectRoot
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Modifier = Join-Path $ScriptDir "modify_patch166.js"

Write-Host "[1/5] Checking required source structure..."
if (!(Test-Path "lib\services\excel_import_service.dart")) { throw "excel_import_service.dart not found." }
if (!(Test-Path "supabase\functions\export-shipment-excel\index.ts")) { throw "export-shipment-excel index.ts not found." }

$excelText = Get-Content -Raw -Encoding UTF8 "lib\services\excel_import_service.dart"
if ($excelText -notlike "*Future<int> _importLocalDeliveryProfiles(*") {
  throw "Local delivery importer function not found. No files changed."
}
if ($excelText -notlike "*_findLocalDeliveryHeader(*") {
  throw "Local delivery header parser not found. No files changed."
}
$exportText = Get-Content -Raw -Encoding UTF8 "supabase\functions\export-shipment-excel\index.ts"
if ($exportText -notlike "*function normalizePhone(value: unknown): string {*") {
  throw "Exporter normalizePhone anchor not found. No files changed."
}
if ($exportText -notlike "*wireStatementAutomationFormulas(files, routeKey);*") {
  throw "Exporter statement automation anchor not found. No files changed."
}

Write-Host "[2/5] Checking Patch166 modifier..."
if (!(Test-Path $Modifier)) { throw "modify_patch166.js not found." }
node --check $Modifier
if ($LASTEXITCODE -ne 0) { throw "Patch166 modifier syntax check failed." }

Write-Host "[3/5] Applying new delivery section / Pay in advance logic..."
node $Modifier $ProjectRoot | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Patch166 source modification failed." }

Write-Host "[4/5] Checking patch integrity..."
git diff --check | Out-Host
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

Write-Host "[5/5] Patch166 applied successfully."
Write-Host ""
Write-Host "Next:"
Write-Host "  1) flutter analyze"
Write-Host "  2) npx supabase functions deploy export-shipment-excel"
Write-Host "  3) Re-upload the revised SEA/AIR BASE Excel and test"
Write-Host ""
Write-Host "No new SQL is required for Patch166."
Write-Host ""
Write-Host "Changed files:"
git diff --name-only | Out-Host

# Remove temporary modifier after successful application.
try { Remove-Item -Force $Modifier -ErrorAction SilentlyContinue } catch {}
