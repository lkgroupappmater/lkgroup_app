$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$f = Join-Path $project "lib\screens\statement_preview_dialog.dart"

if (!(Test-Path -LiteralPath $f)) {
  throw "Missing file: $f"
}

$s = Get-Content -LiteralPath $f -Raw -Encoding UTF8

# Critical painter fix:
# The visible table has 14 columns including No., but the statement values list
# still had one obsolete extra value after MoneyFormat.usd(f.amountUsd).
# That caused cols[col + 2] to run past the end and stopped CustomPainter midway.
$pattern = "(?s)(f == null \? '-' : MoneyFormat\.usd\(f\.amountUsd\),)\s*\r?\n\s*actualWins \? .*?\r?\n\s*\];"
$replacement = '$1' + [Environment]::NewLine + '      ];'

if ([regex]::IsMatch($s, $pattern)) {
  $s = [regex]::Replace($s, $pattern, $replacement, 1)
  Write-Host "FIXED: obsolete statement row value removed" -ForegroundColor Green
} else {
  Write-Host "NOTE: obsolete statement row value pattern not found" -ForegroundColor Yellow
}

# Keep one blank row after actual cargo, with minimum 10 visible rows.
$s = $s.Replace(
  "int get _visibleRows => _rows.length < 10 ? 10 : _rows.length;",
  "int get _visibleRows => _rows.length + 1 < 10 ? 10 : _rows.length + 1;"
)
$s = $s.Replace(
  "final rowCount = rows.length < 10 ? 10 : rows.length;",
  "final rowCount = rows.length + 1 < 10 ? 10 : rows.length + 1;"
)

# Make bottom action area explicit.
$s = $s.Replace(
  "            Padding(" + [Environment]::NewLine + "              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),",
  "            Container(" + [Environment]::NewLine + "              color: Colors.white," + [Environment]::NewLine + "              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),"
)

[System.IO.File]::WriteAllText(
  $f,
  $s,
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Patch109 statement render hotfix applied." -ForegroundColor Cyan
Write-Host "Next:"
Write-Host "flutter analyze"
Write-Host "flutter run"
