$ErrorActionPreference = 'Stop'

function Save-Utf8([string]$path,[string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

function Normalize-Quotation([string]$t) {
  $classMark='class _QuotationFormPainter extends CustomPainter'
  $classStart=$t.IndexOf($classMark)
  if($classStart -lt 0){ throw 'quotation class not found' }

  # 호출부(클래스 선언 이전)에서 routeLabel 중복 제거 후 누락 보강.
  $prefix=$t.Substring(0,$classStart)
  $suffix=$t.Substring($classStart)

  $prefix=[regex]::Replace(
    $prefix,
    "(routeLabel:\s*widget\.routeLabel,\s*){2,}",
    "routeLabel: widget.routeLabel,`r`n      "
  )

  $callMatches=[regex]::Matches($prefix,"_QuotationFormPainter\(")
  for($i=$callMatches.Count-1;$i-ge 0;$i--){
    $m=$callMatches[$i]
    $after=$prefix.Substring($m.Index,[Math]::Min(220,$prefix.Length-$m.Index))
    if($after -notmatch "routeLabel:\s*widget\.routeLabel"){
      $insertAt=$m.Index+$m.Length
      $prefix=$prefix.Insert($insertAt,"`r`n      routeLabel: widget.routeLabel,")
    }
  }

  $t=$prefix+$suffix
  $classStart=$t.IndexOf($classMark)

  # constructor를 정확히 통째로 교체.
  $ctorStart=$t.IndexOf("  const _QuotationFormPainter(",$classStart)
  if($ctorStart -lt 0){ throw 'quotation ctor start not found' }
  $ctorEnd=$t.IndexOf("  });",$ctorStart)
  if($ctorEnd -lt 0){ throw 'quotation ctor end not found' }
  $ctorEnd += "  });".Length

  $ctor=@'
  const _QuotationFormPainter({
    required this.routeLabel,
    required this.template,
    required this.boxes,
    required this.result,
    required this.rates,
    required this.issuedAt,
    required this.config,
    required this.detailRows,
  });
'@
  $t=$t.Remove($ctorStart,$ctorEnd-$ctorStart).Insert($ctorStart,$ctor)

  # field 영역의 routeLabel 중복 제거 후 1개만 삽입.
  $classStart=$t.IndexOf($classMark)
  $staticStart=$t.IndexOf("  static const List<double> xRatio",$classStart)
  if($staticStart -lt 0){ throw 'quotation static anchor not found' }
  $fieldBlock=$t.Substring($classStart,$staticStart-$classStart)
  $fieldBlock=[regex]::Replace($fieldBlock,"\s*final String routeLabel;\s*","`r`n")
  $templatePos=$fieldBlock.IndexOf("  final ui.Image template;")
  if($templatePos -lt 0){ throw 'quotation template field not found' }
  $fieldBlock=$fieldBlock.Insert($templatePos,"  final String routeLabel;`r`n")
  $t=$t.Substring(0,$classStart)+$fieldBlock+$t.Substring($staticStart)

  return $t
}

function Normalize-Statement([string]$t) {
  $classMark='class _StatementPainter extends CustomPainter'
  $classStart=$t.IndexOf($classMark)
  if($classStart -lt 0){ throw 'statement class not found' }

  $prefix=$t.Substring(0,$classStart)
  $suffix=$t.Substring($classStart)

  $prefix=[regex]::Replace(
    $prefix,
    "(routeLabel:\s*widget\.routeLabel,\s*){2,}",
    "routeLabel: widget.routeLabel,`r`n        "
  )

  $callMatches=[regex]::Matches($prefix,"_StatementPainter\(")
  for($i=$callMatches.Count-1;$i-ge 0;$i--){
    $m=$callMatches[$i]
    $after=$prefix.Substring($m.Index,[Math]::Min(260,$prefix.Length-$m.Index))
    if($after -notmatch "routeLabel:\s*widget\.routeLabel"){
      # template line 다음에 넣는 게 가장 안전.
      $templateIdx=$prefix.IndexOf("template: image,",$m.Index)
      if($templateIdx -lt 0){ throw 'statement call template arg not found' }
      $insertAt=$templateIdx+"template: image,".Length
      $prefix=$prefix.Insert($insertAt,"`r`n        routeLabel: widget.routeLabel,")
    }
  }

  $t=$prefix+$suffix
  $classStart=$t.IndexOf($classMark)

  # 기존 field에서 freight 타입 추출.
  $paintStart=$t.IndexOf("  @override",$classStart)
  if($paintStart -lt 0){ throw 'statement override anchor not found' }
  $oldHeader=$t.Substring($classStart,$paintStart-$classStart)
  $m=[regex]::Match($oldHeader,"final\s+([A-Za-z0-9_<>,? ]+)\s+freight;")
  if(!$m.Success){ throw 'statement freight type not found' }
  $freightType=$m.Groups[1].Value.Trim()

  $header=@"
class _StatementPainter extends CustomPainter {
  const _StatementPainter({
    required this.template,
    required this.routeLabel,
    required this.rows,
    required this.freight,
    required this.receiptNumber,
    required this.arrivalDate,
    required this.baseRows,
    required this.detailRows,
  });

  final ui.Image template;
  final String routeLabel;
  final List<Map<String, dynamic>> rows;
  final $freightType freight;
  final String receiptNumber;
  final String? arrivalDate;
  final int baseRows;
  final int detailRows;

"@

  $t=$t.Substring(0,$classStart)+$header+$t.Substring($paintStart)
  return $t
}

$p='lib/screens/quotation_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p
$t=Normalize-Quotation $t
Save-Utf8 $p $t

$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p
$t=Normalize-Statement $t
Save-Utf8 $p $t

Write-Host ''
Write-Host 'Patch098 완료: routeLabel 중복/constructor 구조 정밀 복구'
Write-Host 'flutter analyze 실행하세요.'
