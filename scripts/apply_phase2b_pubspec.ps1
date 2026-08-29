$ErrorActionPreference = 'Stop'
$path = "pubspec.yaml"
if (!(Test-Path $path)) { throw "pubspec.yaml을 찾을 수 없습니다." }

$text = Get-Content -Raw -Encoding UTF8 $path
$assetLine = "    - assets/quotation_forms/"

if (!$text.Contains($assetLine)) {
    $needle = "  assets:`r`n    - assets/images/company_logo_transparent.png"
    if (!$text.Contains($needle)) {
        $needle = "  assets:`n    - assets/images/company_logo_transparent.png"
    }
    if (!$text.Contains($needle)) {
        throw "pubspec.yaml assets 위치를 찾지 못했습니다."
    }

    $replacement = $needle.Replace(
        "    - assets/images/company_logo_transparent.png",
        "    - assets/images/company_logo_transparent.png`r`n    - assets/quotation_forms/"
    )
    $text = $text.Replace($needle, $replacement)
}

Set-Content -Path $path -Value $text -Encoding UTF8
Write-Host "quotation_forms asset 등록 완료"
