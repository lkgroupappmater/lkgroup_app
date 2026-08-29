$ErrorActionPreference = 'Stop'

function Save-Utf8([string]$path,[string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

# QUOTATION
$p='lib/screens/quotation_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# Patch092 routeLabel painter parameter is retained, but displayed title now comes from RouteCatalog.documentTitleFor.
$t=$t.Replace(
  "'`$routeLabel 가견적'",
  "'`${RouteCatalog.documentTitleFor(routeLabel)} 견적서'"
)

# If Patch092 exact syntax uses "$routeLabel 가견적"
$t=$t.Replace(
  "'$routeLabel 가견적'",
  "'`${RouteCatalog.documentTitleFor(routeLabel)} 견적서'"
)

# add remark near lower document area if not present
if(!$t.Contains('RouteCatalog.remarkFor(routeLabel)')) {
  $anchor="    final receipt = RouteCatalog.receiptExampleFor(routeLabel);"
  $insert=@'
    final remark = RouteCatalog.remarkFor(routeLabel);
    if (remark.isNotEmpty) {
      final remarkRect = Rect.fromLTRB(
        _w * .025,
        template.height * .875 + _extraHeight,
        _w * .72,
        template.height * .915 + _extraHeight,
      );
      _clear(canvas, remarkRect);
      _text(
        canvas,
        'Remark: $remark',
        remarkRect,
        20,
      );
    }

'@
  $idx=$t.IndexOf($anchor)
  if($idx -lt 0){ throw 'quotation remark anchor not found' }
  $t=$t.Insert($idx,$insert)
}
Save-Utf8 $p $t

# STATEMENT
$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

$t=$t.Replace(
  "text: '`$routeLabel 거래 명세서',",
  "text: '`${RouteCatalog.documentTitleFor(routeLabel)} xxth 거래 명세서',"
)
$t=$t.Replace(
  "text: '$routeLabel 거래 명세서',",
  "text: '`${RouteCatalog.documentTitleFor(routeLabel)} xxth 거래 명세서',"
)

if(!$t.Contains('final routeRemark = RouteCatalog.remarkFor(routeLabel);')) {
  $anchor="    final shift = extra;"
  $insert=@'
    final routeRemark = RouteCatalog.remarkFor(routeLabel);
    if (routeRemark.isNotEmpty) {
      _text(
        canvas,
        'Remark: $routeRemark',
        Offset(w * .03, h * .58 + extra),
        w * .62,
        fontSize: w * .010,
      );
    }

'@
  $idx=$t.IndexOf($anchor)
  if($idx -lt 0){ throw 'statement remark anchor not found' }
  $t=$t.Insert($idx,$insert)
}
Save-Utf8 $p $t

Write-Host ''
Write-Host 'Patch093 문서 메타데이터 UI/폼 적용 완료'
