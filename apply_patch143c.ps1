$ErrorActionPreference = "Stop"

function Replace-Once([string]$src,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($src,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $src.Replace($old,$new)
}

# Patch143/143b 중간 적용 상태 전용.
# 이미 적용된 cargo_management_screen.dart / quote_request_screen.dart는 건드리지 않습니다.

# ------------------------------------------------------------
# quotation_preview_dialog.dart
# ------------------------------------------------------------
$path = "lib/screens/quotation_preview_dialog.dart"
$src = Get-Content $path -Raw -Encoding UTF8

if ($src -notmatch "receipt_extra_cost_service.dart") {
  $src = Replace-Once $src `
    "import '../services/quote_freight_calculator.dart';" `
    "import '../services/quote_freight_calculator.dart';`r`nimport '../services/receipt_extra_cost_service.dart';" `
    "quotation import"
}

# Widget constructor만 정확히 수정
if ($src -notmatch "this\.extraCosts = const <ExtraCostItem>\[\]") {
  $old = @'
  const QuotationPreviewDialog({
    super.key,
    required this.routeLabel,
    required this.boxes,
    required this.result,
    required this.rates,
  });
'@
  $new = @'
  const QuotationPreviewDialog({
    super.key,
    required this.routeLabel,
    required this.boxes,
    required this.result,
    required this.rates,
    this.extraCosts = const <ExtraCostItem>[],
  });
'@
  $src = Replace-Once $src $old $new "quotation widget ctor"
}

if ($src -notmatch "final List<ExtraCostItem> extraCosts;") {
  $src = Replace-Once $src `
    "  final ExchangeRateSettings rates;`r`n`r`n  @override" `
    "  final ExchangeRateSettings rates;`r`n  final List<ExtraCostItem> extraCosts;`r`n`r`n  @override" `
    "quotation widget field"
}

if ($src -notmatch "extraCosts: widget\.extraCosts") {
  $src = Replace-Once $src `
    "        rates: widget.rates,`r`n        issuedAt: _issuedAt," `
    "        rates: widget.rates,`r`n        extraCosts: widget.extraCosts,`r`n        issuedAt: _issuedAt," `
    "quotation painter call"
}

# Painter ctor만 정확히 수정
if ($src -notmatch "required this\.extraCosts") {
  $old = @'
  const _DigitalQuotationPainter({
    required this.routeLabel,
    required this.boxes,
    required this.result,
    required this.rates,
    required this.issuedAt,
'@
  $new = @'
  const _DigitalQuotationPainter({
    required this.routeLabel,
    required this.boxes,
    required this.result,
    required this.rates,
    required this.extraCosts,
    required this.issuedAt,
'@
  $src = Replace-Once $src $old $new "quotation painter ctor"
}

# painter field는 issuedAt 바로 앞에 삽입
if (([regex]::Matches($src,"final List<ExtraCostItem> extraCosts;")).Count -lt 2) {
  $old = @'
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;
  final DateTime issuedAt;
'@
  $new = @'
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;
  final List<ExtraCostItem> extraCosts;
  final DateTime issuedAt;
'@
  $src = Replace-Once $src $old $new "quotation painter field"
}

if ($src -notmatch "final extraTotal = extraCosts\.fold") {
  $src = Replace-Once $src `
    "    final usd = result.totalUsd;" `
    "    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);`r`n    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');`r`n    final usd = result.totalUsd + extraTotal;" `
    "quotation total"

  $old = @'
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@
  $new = @'
    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 ($extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, extraTotal > 0 ? '+${MoneyFormat.usd(extraTotal)}' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@
  $src = Replace-Once $src $old $new "quotation extra row"
}

Set-Content $path $src -Encoding UTF8

# ------------------------------------------------------------
# statement_preview_dialog.dart
# ------------------------------------------------------------
$path = "lib/screens/statement_preview_dialog.dart"
$src = Get-Content $path -Raw -Encoding UTF8

if ($src -notmatch "receipt_extra_cost_service.dart") {
  $src = Replace-Once $src `
    "import '../services/customer_benefit_service.dart';" `
    "import '../services/customer_benefit_service.dart';`r`nimport '../services/receipt_extra_cost_service.dart';" `
    "statement import"
}

if ($src -notmatch "_extraCosts = const <ExtraCostItem>\[\]") {
  $src = Replace-Once $src `
    "  String _inlandDeliveryText = '';" `
    "  String _inlandDeliveryText = '';`r`n  List<ExtraCostItem> _extraCosts = const <ExtraCostItem>[];" `
    "statement state"
}

if ($src -notmatch "final extraCosts = await ReceiptExtraCostService\.instance\.list") {
  $old = @'
      final inland = await CustomerBenefitService.instance
          .inlandTextForRows(widget.routeLabel, rows);
'@
  $new = @'
      final inland = await CustomerBenefitService.instance
          .inlandTextForRows(widget.routeLabel, rows);
      final extraCosts = await ReceiptExtraCostService.instance.list(
        route: widget.routeLabel,
        year: widget.year,
        voyage: widget.voyage,
        receiptNumber: widget.receiptNumber,
      );
'@
  $src = Replace-Once $src $old $new "statement load extra"

  $src = Replace-Once $src `
    "        _inlandDeliveryText = inland;`r`n        _loading = false;" `
    "        _inlandDeliveryText = inland;`r`n        _extraCosts = extraCosts;`r`n        _loading = false;" `
    "statement set extra"
}

if ($src -notmatch "extraCosts: _extraCosts") {
  $src = Replace-Once $src `
    "        inlandDeliveryText: _inlandDeliveryText,`r`n        logo: _logo!," `
    "        inlandDeliveryText: _inlandDeliveryText,`r`n        extraCosts: _extraCosts,`r`n        logo: _logo!," `
    "statement painter call"
}

if ($src -notmatch "required this\.extraCosts") {
  $old = @'
  const _DigitalStatementPainter({
    required this.routeLabel,
    required this.rows,
    required this.freight,
    required this.receiptNumber,
    required this.arrivalDate,
    required this.inlandDeliveryText,
    required this.logo,
'@
  $new = @'
  const _DigitalStatementPainter({
    required this.routeLabel,
    required this.rows,
    required this.freight,
    required this.receiptNumber,
    required this.arrivalDate,
    required this.inlandDeliveryText,
    required this.extraCosts,
    required this.logo,
'@
  $src = Replace-Once $src $old $new "statement painter ctor"
}

if ($src -notmatch "final List<ExtraCostItem> extraCosts;") {
  $src = Replace-Once $src `
    "  final String inlandDeliveryText;`r`n  final ui.Image logo;" `
    "  final String inlandDeliveryText;`r`n  final List<ExtraCostItem> extraCosts;`r`n  final ui.Image logo;" `
    "statement painter field"
}

# Batch renderer용 extra cost 로드/전달
if ($src -notmatch "receiptNumber: request\.receiptNumber,\s*\r?\n\s*\);\s*\r?\n\s*\r?\n\s*final painter = _DigitalStatementPainter\(") {
  $needle = "    final painter = _DigitalStatementPainter("
  $idx = $src.LastIndexOf($needle)
  if ($idx -lt 0) { throw "안전 중단 [statement batch]: painter 위치 없음" }
  $insert = @'
    final extraCosts = await ReceiptExtraCostService.instance.list(
      route: request.routeLabel,
      year: request.year,
      voyage: request.voyage,
      receiptNumber: request.receiptNumber,
    );

'@
  $src = $src.Insert($idx,$insert)
}

# 배치 painter의 inland 뒤 extraCosts 추가 (마지막 painter 구간만)
if (([regex]::Matches($src,"extraCosts: extraCosts")).Count -eq 0) {
  $needle = "    final painter = _DigitalStatementPainter("
  $idx = $src.LastIndexOf($needle)
  $tail = $src.Substring($idx)
  $old = "      inlandDeliveryText: inland,`r`n      logo: assets[0],"
  $count = ([regex]::Matches($tail,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [statement batch arg]: 대상=$count" }
  $tail = $tail.Replace($old,"      inlandDeliveryText: inland,`r`n      extraCosts: extraCosts,`r`n      logo: assets[0],")
  $src = $src.Substring(0,$idx) + $tail
}

if ($src -notmatch "final finalUsd = freight\.totalUsd \+ extraTotal") {
  $src = Replace-Once $src `
    "    final totalX = leftW + 6;" `
    "    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);`r`n    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');`r`n    final finalUsd = freight.totalUsd + extraTotal;`r`n`r`n    final totalX = leftW + 6;" `
    "statement total vars"

  $old = @'
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@
  $new = @'
    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 ($extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, extraTotal > 0 ? '+${MoneyFormat.usd(extraTotal)}' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@
  $src = Replace-Once $src $old $new "statement extra row"

  $src = Replace-Once $src `
    "    _text(c, 'USD    ' + MoneyFormat.usd(freight.totalUsd)," `
    "    _text(c, 'USD    ' + MoneyFormat.usd(finalUsd)," `
    "statement usd"
  $src = Replace-Once $src `
    "    _text(c, 'KIP    ' + MoneyFormat.kip(freight.totalKip)," `
    "    _text(c, 'KIP    ' + MoneyFormat.kip(finalUsd * freight.rates.appliedKip)," `
    "statement kip"
  $src = Replace-Once $src `
    "    _text(c, 'THB    ' + MoneyFormat.thb(freight.totalThb)," `
    "    _text(c, 'THB    ' + MoneyFormat.thb(finalUsd * freight.rates.appliedThb)," `
    "statement thb"
  $src = Replace-Once $src `
    "    _text(c, 'KRW    ' + MoneyFormat.krw(freight.totalKrw)," `
    "    _text(c, 'KRW    ' + MoneyFormat.krw(finalUsd * freight.rates.appliedKrw)," `
    "statement krw"
}

Set-Content $path $src -Encoding UTF8

Write-Host "Patch143c 적용 완료"
Write-Host "flutter analyze 를 실행해 주세요."
