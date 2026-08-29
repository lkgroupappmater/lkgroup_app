$ErrorActionPreference = 'Stop'

function Save-Utf8([string]$path,[string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

# =========================================================
# quotation_preview_dialog.dart
# =========================================================
$p='lib/screens/quotation_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# 1) 두 호출부를 통째로 정상 형태로 교체
$callPattern = "_QuotationFormPainter\([\s\S]*?detailRows:\s*_detailRows,\s*\)"
$matches = [regex]::Matches($t,$callPattern)
if($matches.Count -lt 2) {
  throw "quotation painter call blocks not found: $($matches.Count)"
}

$normalCall = @'
_QuotationFormPainter(
      routeLabel: widget.routeLabel,
      template: image,
      boxes: widget.boxes,
      result: widget.result,
      rates: widget.rates,
      issuedAt: _issuedAt,
      config: _config,
      detailRows: _detailRows,
    )
'@

# 뒤에서부터 교체해서 index 변동 방지
for($i=$matches.Count-1; $i -ge 0; $i--) {
  $m=$matches[$i]
  $t=$t.Remove($m.Index,$m.Length).Insert($m.Index,$normalCall)
}

# 2) Painter constructor + field 구간을 통째로 정상화
$classStart=$t.IndexOf("class _QuotationFormPainter extends CustomPainter")
if($classStart -lt 0){ throw 'quotation painter class not found' }

$listStart=$t.IndexOf("  static const List<double> xRatio",$classStart)
if($listStart -lt 0){ throw 'quotation xRatio anchor not found' }

$header=@'
class _QuotationFormPainter extends CustomPainter {
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

  final String routeLabel;
  final ui.Image template;
  final List<QuotationPreviewBox> boxes;
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;
  final DateTime issuedAt;
  final _RouteFormConfig config;
  final int detailRows;

'@

$t=$t.Substring(0,$classStart)+$header+$t.Substring($listStart)

# 3) 호출부 들여쓰기 차이만 formatter가 처리. stale _routeKey getter는 유지해도 compile 무관.
Save-Utf8 $p $t

# =========================================================
# statement_preview_dialog.dart
# =========================================================
$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# StatementPainter 호출부: template~detailRows 블록을 정상화
$callPattern = "_StatementPainter\([\s\S]*?detailRows:\s*_detailRows,\s*\)"
$matches = [regex]::Matches($t,$callPattern)
if($matches.Count -lt 1) {
  throw "statement painter call block not found"
}

# 기존 호출부에서 필요한 variable names는 현재 화면 기준 동일
$normalCall = @'
_StatementPainter(
        template: image,
        routeLabel: widget.routeLabel,
        rows: widget.rows,
        freight: widget.freight,
        receiptNumber: widget.receiptNumber,
        arrivalDate: widget.arrivalDate,
        baseRows: _baseRows,
        detailRows: _detailRows,
      )
'@

# 첫/모든 호출을 같은 형태로 교체
for($i=$matches.Count-1; $i -ge 0; $i--) {
  $m=$matches[$i]
  $t=$t.Remove($m.Index,$m.Length).Insert($m.Index,$normalCall)
}

# constructor + fields를 통째로 정상화하되 freight 실제 타입은 기존 field에서 추출
$classStart=$t.IndexOf("class _StatementPainter extends CustomPainter")
if($classStart -lt 0){ throw 'statement painter class not found' }

$paintStart=$t.IndexOf("  @override`r`n  void paint(Canvas canvas, Size size)",$classStart)
if($paintStart -lt 0) {
  $paintStart=$t.IndexOf("  @override`n  void paint(Canvas canvas, Size size)",$classStart)
}
if($paintStart -lt 0){ throw 'statement paint anchor not found' }

# 현재 프로젝트에 맞는 freight 타입 자동 추출
$fieldArea=$t.Substring($classStart,$paintStart-$classStart)
$typeMatch=[regex]::Match($fieldArea,"final\s+([A-Za-z0-9_<>?, ]+)\s+freight;")
if(!$typeMatch.Success){ throw 'statement freight type not found' }
$freightType=$typeMatch.Groups[1].Value.Trim()

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

Save-Utf8 $p $t

Write-Host ''
Write-Host 'Patch097 완료: quotation/statement Painter constructor/call 전체 복구'
Write-Host '이제 flutter analyze 실행'
