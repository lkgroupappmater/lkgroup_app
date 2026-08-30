$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
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
[System.IO.File]::WriteAllText(
    $pub,
    $text,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "Patch106 assets registered."
