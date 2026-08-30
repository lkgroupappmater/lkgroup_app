$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $project "_patch106c"

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
  $dst = Join-Path $project $rel
  if (-not (Test-Path -LiteralPath $src)) {
    throw "Missing staged file: $src"
  }
  $dir = Split-Path -Parent $dst
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Copy-Item -LiteralPath $src -Destination $dst -Force
  Write-Host "REPLACED: $rel"
}

$pub = Join-Path $project "pubspec.yaml"
$text = Get-Content -LiteralPath $pub -Raw -Encoding UTF8
$assets = @(
  "    - assets/images/bank_accounts_default.png",
  "    - assets/images/bank_accounts_vat.png",
  "    - assets/images/company_stamp.png"
)
$anchor = "    - assets/images/company_logo.png"
foreach ($asset in $assets) {
  if ($text -notmatch [regex]::Escape($asset)) {
    if (-not $text.Contains($anchor)) {
      throw "pubspec asset anchor not found"
    }
    $text = $text.Replace($anchor, $anchor + [Environment]::NewLine + $asset)
  }
}
[System.IO.File]::WriteAllText($pub,$text,[System.Text.UTF8Encoding]::new($false))

$q = Get-Content -LiteralPath (Join-Path $project "lib\screens\quotation_preview_dialog.dart") -Raw -Encoding UTF8
$s = Get-Content -LiteralPath (Join-Path $project "lib\screens\statement_preview_dialog.dart") -Raw -Encoding UTF8

$checks = @(
  @("quotation centered info", $q.Contains("final leftWInfo = w * .56;")),
  @("quotation VAT bank", $q.Contains("bankStripVat")),
  @("quotation two-line address", $q.Contains("LK Trading")),
  @("statement centered info", $s.Contains("final leftWInfo = w * .56;")),
  @("statement VAT bank", $s.Contains("bankStripVat"))
)

foreach ($c in $checks) {
  if (-not $c[1]) {
    throw ("VERIFY FAILED: " + $c[0])
  }
  Write-Host ("VERIFY OK: " + $c[0]) -ForegroundColor Green
}

Write-Host ""
Write-Host "Patch106c force apply complete." -ForegroundColor Cyan
Write-Host "Run these next:"
Write-Host "flutter clean"
Write-Host "flutter pub get"
Write-Host "flutter analyze"
Write-Host "flutter run"
