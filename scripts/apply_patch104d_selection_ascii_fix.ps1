$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$cm = Join-Path $project "lib\screens\cargo_management_screen.dart"

if (-not (Test-Path -LiteralPath $cm)) {
    throw "Missing file: $cm"
}

$text = Get-Content -LiteralPath $cm -Raw -Encoding UTF8

# Remove automatic checking of incoming IDs.
$text = $text -replace "(?m)^\s*_selectedIds\.addAll\(widget\.initialSelectedIds\);\s*\r?\n", ""
$text = $text -replace "if\s*\(widget\.initialSelectedIds\.isEmpty\)\s*_selectedIds\.clear\(\);", "_selectedIds.clear();"

# Dart supports Unicode escapes. This avoids Korean encoding inside this PS1 file.
$msg = "\uC120\uD0DD\uB41C \uD56D\uCC28\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4."

$pattern = "onPressed:\s*_results\.isEmpty\s*\?\s*null\s*:\s*_showAllSearchResultStatements\s*,"
$replacement = @"
onPressed: _results.isEmpty
                          ? null
                          : () {
                              if (_selectedIds.isEmpty) {
                                _message('$msg');
                                return;
                              }
                              _showStatement();
                            },
"@

$options = [System.Text.RegularExpressions.RegexOptions]::Singleline
if ([regex]::IsMatch($text, $pattern, $options)) {
    $text = [regex]::Replace($text, $pattern, $replacement, $options)
} else {
    Write-Host "NOTE: statement button pattern was not found."
}

[System.IO.File]::WriteAllText(
    $cm,
    $text,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Patch104d applied successfully."
Write-Host "1. Incoming cargo rows start unchecked."
Write-Host "2. Statement action requires checked cargo."
Write-Host "Next: flutter analyze"
