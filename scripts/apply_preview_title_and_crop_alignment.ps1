$ErrorActionPreference = 'Stop'

function Save-Utf8([string]$path,[string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

# =========================================================
# 1) 추가 기능 개발: BASE 전체 미리보기 여백 제거 + 확대 + 타이틀 위치 보정
# =========================================================
$p='lib/screens/additional_feature_development_screen.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# Patch100 적용 상태 기준으로 AspectRatio / Image.asset / overlay 위치 정밀 수정
$t=$t.Replace(
"aspectRatio: 1.42,",
"aspectRatio: 1.55,"
)

$t=$t.Replace(
"""                        Image.asset(
                          'assets/statement_forms/$formKey.png',
                          fit: BoxFit.contain,
                          alignment: Alignment.topCenter,""",
"""                        Image.asset(
                          'assets/statement_forms/$formKey.png',
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.bottomCenter,"""
)

# 타이틀 overlay는 잘려진 실문서 상단 타이틀 줄에 맞춤
$t=$t.Replace(
"""                            left: constraints.maxWidth * .20,
                            right: constraints.maxWidth * .20,
                            top: constraints.maxHeight * .012,
                            height: constraints.maxHeight * .065,""",
"""                            left: constraints.maxWidth * .18,
                            right: constraints.maxWidth * .18,
                            top: constraints.maxHeight * .018,
                            height: constraints.maxHeight * .090,"""
)

# receipt 위치도 실문서 상단 우측 번호칸에 맞춤
$t=$t.Replace(
"""                            right: constraints.maxWidth * .018,
                            top: constraints.maxHeight * .105,
                            width: constraints.maxWidth * .14,
                            height: constraints.maxHeight * .045,""",
"""                            right: constraints.maxWidth * .018,
                            top: constraints.maxHeight * .028,
                            width: constraints.maxWidth * .16,
                            height: constraints.maxHeight * .075,"""
)

Save-Utf8 $p $t

# =========================================================
# 2) 견적서: 메뉴 표시명이 아니라 document_title 사용 + 원본 타이틀 크기/위치에 맞춤
# =========================================================
$p='lib/screens/quotation_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

$old=@'
  void _paintRouteHeader(Canvas canvas) {
    // 기존 BASE의 레이아웃만 사용하고 노선 고유 타이틀은 현재 경로명으로 다시 표시.
    final h = template.height.toDouble();
    final titleRect = Rect.fromLTRB(_w * .22, h * .012, _w * .78, h * .09);
    _clear(canvas, titleRect);
    _text(
      canvas,
      '${routeLabel} 견적서',
      titleRect,
      30,
      bold: true,
    );

    final receipt = RouteCatalog.receiptExampleFor(routeLabel);
'@

$new=@'
  void _paintRouteHeader(Canvas canvas) {
    // BASE는 레이아웃만 사용하고 문서용 타이틀은 DB document_title 기준으로 표시.
    final h = template.height.toDouble();
    final documentTitle = RouteCatalog.documentTitleFor(routeLabel);
    final titleRect = Rect.fromLTRB(_w * .19, h * .018, _w * .81, h * .108);
    _clear(canvas, titleRect);
    _text(
      canvas,
      '$documentTitle xxth 견적서',
      titleRect,
      48,
      bold: true,
    );

    final receipt = RouteCatalog.receiptExampleFor(routeLabel);
'@

if(-not $t.Contains($old)){ throw 'quotation _paintRouteHeader anchor not found' }
$t=$t.Replace($old,$new)

Save-Utf8 $p $t

# =========================================================
# 3) 거래 명세서: 실제 문서 타이틀 위치(.39 부근) + document_title 사용
# =========================================================
$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

$old=@'
  void _paintRouteTitle(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTRB(w * .20, h * .01, w * .80, h * .075);
    canvas.drawRect(
      rect,
      Paint()..color = Colors.white,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: '$routeLabel 거래 명세서',
        style: TextStyle(
          color: Colors.black,
          fontFamily: 'NotoSansKR',
          fontSize: w * .028,
          fontWeight: FontWeight.w700,
        ),
      ),
'@

$new=@'
  void _paintRouteTitle(Canvas canvas, double w, double h) {
    final documentTitle = RouteCatalog.documentTitleFor(routeLabel);
    // statement PNG는 상단에 원본 링크 이미지 여백이 있으므로 실제 문서 타이틀 위치에 덮어씀.
    final rect = Rect.fromLTRB(w * .18, h * .388, w * .82, h * .447);
    canvas.drawRect(
      rect,
      Paint()..color = Colors.white,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: '$documentTitle xxth 거래 명세서',
        style: TextStyle(
          color: Colors.black,
          fontFamily: 'NotoSansKR',
          fontSize: w * .030,
          fontWeight: FontWeight.w700,
        ),
      ),
'@

if(-not $t.Contains($old)){ throw 'statement _paintRouteTitle anchor not found' }
$t=$t.Replace($old,$new)

Save-Utf8 $p $t

Write-Host ''
Write-Host 'Patch101 완료'
Write-Host '- BASE 미리보기 상단 불필요 여백 crop + 확대'
Write-Host '- 견적서 타이틀 document_title 적용'
Write-Host '- 명세서 타이틀 document_title 및 실제 위치 보정'
Write-Host 'flutter analyze 실행하세요.'
