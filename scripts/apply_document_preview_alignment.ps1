$ErrorActionPreference = 'Stop'

function Save-Utf8([string]$path,[string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

# ============================================================
# A. 운송 경로 편집 BASE 미리보기
# 실제 문서 영역은 source PNG의 하단 약 760px.
# 화면 aspect ratio를 실제 문서 비율에 맞춰 crop하여 흰 여백 제거.
# ============================================================
$p='lib/screens/additional_feature_development_screen.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# Patch102 기준 aspect ratio를 실제 document crop 비율로 수정
$t=$t.Replace('aspectRatio: 1.78,','aspectRatio: 1.95,')

# 제목 overlay 크기/위치: 실제 문서 첫 header row 기준
$t=$t.Replace(
"""                            left: constraints.maxWidth * .18,
                            right: constraints.maxWidth * .18,
                            top: constraints.maxHeight * .015,
                            height: constraints.maxHeight * .115,""",
"""                            left: constraints.maxWidth * .19,
                            right: constraints.maxWidth * .19,
                            top: constraints.maxHeight * .020,
                            height: constraints.maxHeight * .082,"""
)

# 제목 font를 실제 header 비율에 맞게 작게
$t=$t.Replace(
"""                                    fontSize: 15,""",
"""                                    fontSize: 12,"""
)

# receipt header 위치/크기 보정
$t=$t.Replace(
"""                            right: constraints.maxWidth * .010,
                            top: constraints.maxHeight * .018,
                            width: constraints.maxWidth * .145,
                            height: constraints.maxHeight * .095,""",
"""                            right: constraints.maxWidth * .018,
                            top: constraints.maxHeight * .020,
                            width: constraints.maxWidth * .145,
                            height: constraints.maxHeight * .080,"""
)

Save-Utf8 $p $t

# ============================================================
# B. 실제 거래 명세서 Preview Painter
# 이전 h*.388 위치는 source PNG의 빈 여백 영역이었음.
# 실제 document header는 약 y=671 이후 시작하므로 title을 y=.47 부근에 배치.
# ============================================================
$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

$t=$t.Replace(
"final rect = Rect.fromLTRB(w * .18, h * .388, w * .82, h * .447);",
"final rect = Rect.fromLTRB(w * .19, h * .472, w * .81, h * .525);"
)

# 혹시 Patch101 이전 코드가 남아 있는 경우까지 교정
$t=$t.Replace(
"final rect = Rect.fromLTRB(w * .20, h * .01, w * .80, h * .075);",
"final rect = Rect.fromLTRB(w * .19, h * .472, w * .81, h * .525);"
)

# routeLabel이 남아 있으면 documentTitle 사용
$t=$t.Replace(
"text: '`$routeLabel 거래 명세서',",
"text: '`$documentTitle xxth 거래 명세서',"
)

# documentTitle 선언 누락 보강
$method='  void _paintRouteTitle(Canvas canvas, double w, double h) {'
if($t.Contains($method) -and -not $t.Contains("final documentTitle = RouteCatalog.documentTitleFor(routeLabel);")){
  $t=$t.Replace(
    $method,
    "$method`r`n    final documentTitle = RouteCatalog.documentTitleFor(routeLabel);"
  )
}

Save-Utf8 $p $t

Write-Host ''
Write-Host 'Patch103 Flutter 적용 완료'
Write-Host '- BASE 미리보기 실제 문서 비율 crop'
Write-Host '- 명세서 Painter 실제 title 위치 보정'
Write-Host ''
Write-Host '다음: flutter analyze'
Write-Host 'Edge Function 파일도 ZIP에 포함됨: clone-route-base 재배포 필요'
