$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $project "_rollback"

$files = @(
  "lib\screens\quotation_preview_dialog.dart",
  "lib\screens\statement_preview_dialog.dart",
  "lib\services\document_pdf_export.dart",
  "assets\images\company_stamp.png",
  "assets\images\bank_accounts_default.png",
  "assets\images\bank_accounts_vat.png"
)

foreach ($rel in $files) {
  $src = Join-Path $stage $rel
  if (Test-Path -LiteralPath $src) {
    $dst = Join-Path $project $rel
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "RESTORED: $rel"
  }
}

Write-Host ""
Write-Host "Rollback to Patch105 working files complete." -ForegroundColor Green
Write-Host "Next:"
Write-Host "flutter clean"
Write-Host "flutter pub get"
Write-Host "flutter analyze"
