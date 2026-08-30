$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$q = Join-Path $project "lib\screens\quotation_preview_dialog.dart"
$s = Join-Path $project "lib\screens\statement_preview_dialog.dart"

foreach ($p in @($q,$s)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Missing file: $p"
    }
}

Write-Host "Patch106b files are in place."
Write-Host "Next: flutter analyze"
