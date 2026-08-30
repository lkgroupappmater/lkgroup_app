$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$pub = Join-Path $project "pubspec.yaml"
$text = Get-Content -LiteralPath $pub -Raw -Encoding UTF8
$asset = "    - assets/images/bank_accounts_strip.png"
if ($text -notmatch [regex]::Escape($asset)) {
    $anchor = "    - assets/images/company_logo.png"
    if ($text.Contains($anchor)) {
        $text = $text.Replace($anchor, $anchor + [Environment]::NewLine + $asset)
    } else {
        throw "pubspec asset anchor not found"
    }
}
[System.IO.File]::WriteAllText($pub, $text, [System.Text.UTF8Encoding]::new($false))
Write-Host "Patch105 assets registered."
