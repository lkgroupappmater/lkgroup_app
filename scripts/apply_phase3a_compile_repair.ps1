$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# 1) management_menu_screen.dart
#    PHASE3A PowerShell here-string이 Dart 단일 문자열 안에 실제 줄바꿈을 넣은 문제 수정.
# ------------------------------------------------------------
$path = "lib/screens/management_menu_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$text = Get-Content -Raw -Encoding UTF8 $path

# 실제 개행이 들어간 잘못된 label을 Dart의 \n escape로 교체.
$badLabel = @'
'label': '엑셀 데이타 일괄 관리
(편집 잠금/해제, 구획 및 영수 번호 관리)',
'@

$goodLabel = @'
'label': '엑셀 데이타 일괄 관리\n(편집 잠금/해제, 구획 및 영수 번호 관리)',
'@

if ($text.Contains($badLabel)) {
    $text = $text.Replace($badLabel, $goodLabel)
}

# 이전 패치에서 },        { 로 붙은 부분도 보기 좋게 정상 개행.
$text = $text.Replace("        },        {", "        },`r`n        {")

Set-Content -Path $path -Value $text -Encoding UTF8


# ------------------------------------------------------------
# 2) shipment_service.dart
#    PowerShell이 ${request[...]} 를 변수 보간으로 먹어버려 '\'만 남긴 문제 수정.
# ------------------------------------------------------------
$path = "lib/services/shipment_service.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$text = Get-Content -Raw -Encoding UTF8 $path

$broken = @'
        final route = '\';
        final year = (request['shipment_year'] as num?)?.toInt();
        final voyage = '\';
        final box = '\';
'@

$fixed = @'
        final route = '${request['route'] ?? ''}';
        final year = (request['shipment_year'] as num?)?.toInt();
        final voyage = '${request['voyage'] ?? ''}';
        final box = '${request['box_number'] ?? ''}';
'@

if ($text.Contains($broken)) {
    $text = $text.Replace($broken, $fixed)
} else {
    # CRLF/LF 차이 또는 공백 차이까지 보완.
    $text = [regex]::Replace(
        $text,
        "final route = '\\\\';\s*\r?\n\s*final year = \(request\['shipment_year'\] as num\?\)\?\.toInt\(\);\s*\r?\n\s*final voyage = '\\\\';\s*\r?\n\s*final box = '\\\\';",
        "final route = '`${request['route'] ?? ''}';`r`n        final year = (request['shipment_year'] as num?)?.toInt();`r`n        final voyage = '`${request['voyage'] ?? ''}';`r`n        final box = '`${request['box_number'] ?? ''}';"
    )
}

Set-Content -Path $path -Value $text -Encoding UTF8

Write-Host ""
Write-Host "PHASE 3A compile repair complete."
Write-Host "Now run: flutter analyze"
