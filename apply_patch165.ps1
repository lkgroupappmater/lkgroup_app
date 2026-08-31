param(
  [string]$ProjectRoot = "C:\Users\ssapd\StudioProjects\lkgroup_app"
)

$ErrorActionPreference = "Stop"
$Expected = @{
  "lib/services/excel_import_service.dart" = "e5a633f83cc49cc5c6242aa1564b9bd46b20c3b8"
  "lib/services/customer_benefit_service.dart" = "d105cd4186e122d0c47cb016b8b8a8dd67021668"
  "lib/services/freight_service.dart" = "e4afece805d5a1fec8a6ecfe3d559d896e2a7d3c"
  "lib/screens/change_approval_screen.dart" = "9d2a6c5074412527bd0dc221fdeda6db9db502f7"
  "lib/screens/statement_preview_dialog.dart" = "5b6d3771bbe5db37b67c20b3cc437202d9eac427"
}

Set-Location $ProjectRoot
Write-Host "[1/6] Checking target files only (local commits are preserved)..."
Write-Host "Local HEAD: $((git rev-parse HEAD).Trim())"
Write-Host "[2/6] Checking target file versions..."
foreach ($rel in $Expected.Keys) {
  $actual = (git hash-object $rel).Trim()
  if ($actual -ne $Expected[$rel]) {
    throw "Target file changed: $rel`nExpected $($Expected[$rel])`nActual   $actual`nNo files changed."
  }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Modifier = Join-Path $ScriptDir "modify_patch165.js"
$SqlPayload = Join-Path $ScriptDir "patch165_payload\supabase_097_patch165_customer_receipt_zone_discount.sql"
if (!(Test-Path $Modifier)) { throw "modify_patch165.js not found." }
if (!(Test-Path $SqlPayload)) { throw "Patch165 SQL payload not found." }

Write-Host "[3/6] Applying Patch165 source changes..."
node $Modifier $ProjectRoot | Out-Host

Write-Host "[4/6] Installing SQL file into project..."
$SqlTarget = Join-Path $ProjectRoot "supabase\supabase_097_patch165_customer_receipt_zone_discount.sql"
Copy-Item -Force $SqlPayload $SqlTarget

Write-Host "[5/6] Checking patch integrity..."
git diff --check | Out-Host
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

Write-Host "[6/6] Patch165 FIX + delivery colors applied successfully."
Write-Host ""
Write-Host "Next:"
Write-Host "  1) flutter analyze"
Write-Host "  2) Run supabase\supabase_097_patch165_customer_receipt_zone_discount.sql in Supabase SQL Editor"
Write-Host "  3) Upload your V08 workbook and test"
Write-Host ""
Write-Host "Changed files:"
git diff --name-only | Out-Host

# Cleanup extracted staging files so they do not remain in the Flutter project.
try { Remove-Item -Force $Modifier -ErrorAction SilentlyContinue } catch {}
try { Remove-Item -Recurse -Force (Join-Path $ScriptDir "patch165_payload") -ErrorAction SilentlyContinue } catch {}
