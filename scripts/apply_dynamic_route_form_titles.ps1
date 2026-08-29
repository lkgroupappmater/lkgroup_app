$ErrorActionPreference = 'Stop'

function Save-Utf8([string]$path,[string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

# ---------------------------
# Quotation preview
# ---------------------------
$p='lib/screens/quotation_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# 두 painter 생성부에 routeLabel 전달
if(!$t.Contains('routeLabel: widget.routeLabel')) {
  $t=$t.Replace(
    "_QuotationFormPainter(`r`n              template: image,",
    "_QuotationFormPainter(`r`n              routeLabel: widget.routeLabel,`r`n              template: image,"
  )
  $t=$t.Replace(
    "_QuotationFormPainter(`n              template: image,",
    "_QuotationFormPainter(`n              routeLabel: widget.routeLabel,`n              template: image,"
  )
  $t=$t.Replace(
    "_QuotationFormPainter(`r`n      template: image,",
    "_QuotationFormPainter(`r`n      routeLabel: widget.routeLabel,`r`n      template: image,"
  )
  $t=$t.Replace(
    "_QuotationFormPainter(`n      template: image,",
    "_QuotationFormPainter(`n      routeLabel: widget.routeLabel,`n      template: image,"
  )
}

# painter constructor + field
if(!$t.Contains('required this.routeLabel')) {
  $t=$t.Replace(
    "  const _QuotationFormPainter({`r`n    required this.template,",
    "  const _QuotationFormPainter({`r`n    required this.routeLabel,`r`n    required this.template,"
  )
  $t=$t.Replace(
    "  const _QuotationFormPainter({`n    required this.template,",
    "  const _QuotationFormPainter({`n    required this.routeLabel,`n    required this.template,"
  )
}
if(!$t.Contains('final String routeLabel;')) {
  $t=$t.Replace(
    "  final ui.Image template;",
    "  final String routeLabel;`r`n  final ui.Image template;"
  )
}

# 실제 그림 위에 신규 경로 타이틀/영수 Prefix 표시
if(!$t.Contains('_paintRouteHeader(canvas);')) {
  $t=$t.Replace(
    "    _paintDate(canvas);",
    "    _paintRouteHeader(canvas);`r`n    _paintDate(canvas);"
  )
}

if(!$t.Contains('void _paintRouteHeader(Canvas canvas)')) {
  $method=@'

  void _paintRouteHeader(Canvas canvas) {
    // 선택한 BASE 이미지는 레이아웃만 상속하고,
    // 운송 경로 고유 타이틀/Prefix는 현재 DB 경로 값으로 다시 그립니다.
    final titleRect = Rect.fromLTRB(
      _w * .245,
      template.height * .018,
      _w * .705,
      template.height * .095,
    );
    _clear(canvas, titleRect);
    _text(
      canvas,
      '$routeLabel 가견적',
      titleRect,
      34,
      bold: true,
    );

    final receipt = RouteCatalog.receiptExampleFor(routeLabel);
    if (receipt.isNotEmpty) {
      final receiptRect = Rect.fromLTRB(
        _w * .895,
        template.height * .100,
        _w * .988,
        template.height * .145,
      );
      _clear(canvas, receiptRect);
      _text(
        canvas,
        receipt,
        receiptRect,
        23,
        bold: true,
      );
    }
  }
'@
  $idx=$t.IndexOf("  void _paintDate(Canvas canvas)")
  if($idx -lt 0){ throw 'quotation _paintDate anchor not found' }
  $t=$t.Insert($idx,$method+"`r`n")
}

Save-Utf8 $p $t

# ---------------------------
# Statement preview
# ---------------------------
$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# _StatementPainter 생성부
if(!$t.Contains('routeLabel: widget.routeLabel')) {
  $t=$t.Replace(
    "        template: image,`r`n        rows:",
    "        template: image,`r`n        routeLabel: widget.routeLabel,`r`n        rows:"
  )
  $t=$t.Replace(
    "        template: image,`n        rows:",
    "        template: image,`n        routeLabel: widget.routeLabel,`n        rows:"
  )
}

if(!$t.Contains('required this.routeLabel')) {
  $t=$t.Replace(
    "    required this.template,`r`n    required this.rows,",
    "    required this.template,`r`n    required this.routeLabel,`r`n    required this.rows,"
  )
  $t=$t.Replace(
    "    required this.template,`n    required this.rows,",
    "    required this.template,`n    required this.routeLabel,`n    required this.rows,"
  )
}

# statement painter 내부 field
$statementClass=$t.IndexOf("class _StatementPainter extends CustomPainter")
if($statementClass -lt 0){ throw 'statement painter class not found' }
if($t.IndexOf("final String routeLabel;",$statementClass) -lt 0) {
  $fieldIdx=$t.IndexOf("  final ui.Image template;",$statementClass)
  if($fieldIdx -lt 0){ throw 'statement template field anchor not found' }
  $insertAt=$fieldIdx + "  final ui.Image template;".Length
  $t=$t.Insert($insertAt,"`r`n  final String routeLabel;")
}

# title overlay
if(!$t.Contains('_paintRouteTitle(canvas, w, h);')) {
  $marker="    // 기존 샘플 값만 흰색으로 지우고 실제 DB 값을 오버레이."
  $idx=$t.IndexOf($marker,$statementClass)
  if($idx -lt 0){ throw 'statement overlay marker not found' }
  $t=$t.Insert($idx,"    _paintRouteTitle(canvas, w, h);`r`n`r`n")
}

if(!$t.Contains('void _paintRouteTitle(Canvas canvas, double w, double h)')) {
  $method=@'

  void _paintRouteTitle(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTRB(
      w * .245,
      h * .012,
      w * .755,
      h * .080,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        rect.left + 1,
        rect.top + 1,
        rect.right - 1,
        rect.bottom - 1,
      ),
      Paint()..color = Colors.white,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: '$routeLabel 거래 명세서',
        style: TextStyle(
          color: Colors.black,
          fontFamily: 'NotoSansKR',
          fontSize: w * .030,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);

    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }
'@
  $idx=$t.IndexOf("  void _text(",$statementClass)
  if($idx -lt 0){ throw 'statement _text anchor not found' }
  $t=$t.Insert($idx,$method+"`r`n")
}

Save-Utf8 $p $t

Write-Host ''
Write-Host 'Patch092 완료: 신규 경로 가견적/명세서 타이틀 동적 반영'
Write-Host 'SQL / Edge Function 재배포 없음'
