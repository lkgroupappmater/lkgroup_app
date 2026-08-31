$ErrorActionPreference = "Stop"

function Read-Utf8([string]$path) {
  if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }
  return Get-Content $path -Raw -Encoding UTF8
}
function Write-Utf8([string]$path,[string]$src) {
  Set-Content $path $src -Encoding UTF8
}
function Ensure-Once([string]$src,[string]$needle,[string]$insertAfter,[string]$label) {
  if ($src.Contains($needle)) { return $src }
  $idx=$src.IndexOf($insertAfter)
  if($idx -lt 0){throw "안전 중단 [$label]: 기준 문자열 없음"}
  $pos=$idx+$insertAfter.Length
  return $src.Insert($pos,$needle)
}
function Replace-Regex-One([string]$src,[string]$pattern,[string]$replacement,[string]$label) {
  $rx=[regex]::new($pattern,[System.Text.RegularExpressions.RegexOptions]::Multiline)
  $m=$rx.Matches($src)
  if($m.Count -ne 1){throw "안전 중단 [$label]: 대상 발견 수=$($m.Count)"}
  return $rx.Replace($src,$replacement,1)
}
function Normalize-Literal-Newlines([string]$src) {
  # Patch143b가 single-quoted replacement에서 넣을 수 있었던 literal `r`n 제거
  return $src.Replace('`r`n',[Environment]::NewLine).Replace('`n',[Environment]::NewLine)
}

# ============================================================
# 0) quote_request_screen.dart : 143b 잔여 literal newline 정리 + 필수 연결 확인
# ============================================================
$path="lib/screens/quote_request_screen.dart"
$src=Normalize-Literal-Newlines (Read-Utf8 $path)

if($src -notmatch "receipt_extra_cost_service\.dart"){
  $src=$src.Replace(
    "import '../services/quote_service.dart';",
    "import '../services/quote_service.dart';"+[Environment]::NewLine+"import '../services/receipt_extra_cost_service.dart';"
  )
}
if($src -notmatch "final List<ExtraCostItem> _extraCosts"){
  $src=$src.Replace(
    "  final List<_BoxEntry> _boxes = [_BoxEntry()];",
    "  final List<_BoxEntry> _boxes = [_BoxEntry()];"+[Environment]::NewLine+"  final List<ExtraCostItem> _extraCosts = <ExtraCostItem>[];"
  )
}
if($src -notmatch "extraCosts:\s*List<ExtraCostItem>\.unmodifiable\(_extraCosts\)"){
  $src=Replace-Regex-One $src `
    '(^\s*rates:\s*rates,\s*$)' `
    ('$1'+[Environment]::NewLine+'        extraCosts: List<ExtraCostItem>.unmodifiable(_extraCosts),') `
    'quote preview args'
}
Write-Utf8 $path $src

# ============================================================
# 1) quotation_preview_dialog.dart
# ============================================================
$path="lib/screens/quotation_preview_dialog.dart"
$src=Normalize-Literal-Newlines (Read-Utf8 $path)

if($src -notmatch "receipt_extra_cost_service\.dart"){
  $src=$src.Replace(
    "import '../services/quote_freight_calculator.dart';",
    "import '../services/quote_freight_calculator.dart';"+[Environment]::NewLine+"import '../services/receipt_extra_cost_service.dart';"
  )
}

# Widget ctor
$widgetStart=$src.IndexOf("class QuotationPreviewDialog extends StatefulWidget")
$stateStart=$src.IndexOf("class _QuotationPreviewDialogState", $widgetStart)
if($widgetStart -lt 0 -or $stateStart -lt 0){throw "안전 중단 [quotation widget section]"}
$widget=$src.Substring($widgetStart,$stateStart-$widgetStart)

if($widget -notmatch "this\.extraCosts\s*="){
  $widget=Replace-Regex-One $widget `
    '(^\s*required this\.rates,\s*$)' `
    ('$1'+[Environment]::NewLine+'    this.extraCosts = const <ExtraCostItem>[],') `
    'quotation widget ctor'
}
if($widget -notmatch "final List<ExtraCostItem> extraCosts;"){
  $widget=Replace-Regex-One $widget `
    '(^\s*final ExchangeRateSettings rates;\s*$)' `
    ('$1'+[Environment]::NewLine+'  final List<ExtraCostItem> extraCosts;') `
    'quotation widget field'
}
$src=$src.Substring(0,$widgetStart)+$widget+$src.Substring($stateStart)

# painter call inside state
$stateStart=$src.IndexOf("class _QuotationPreviewDialogState")
$painterClass=$src.IndexOf("class _DigitalQuotationPainter", $stateStart)
$state=$src.Substring($stateStart,$painterClass-$stateStart)
if($state -notmatch "extraCosts:\s*widget\.extraCosts"){
  $state=Replace-Regex-One $state `
    '(^\s*rates:\s*widget\.rates,\s*$)' `
    ('$1'+[Environment]::NewLine+'        extraCosts: widget.extraCosts,') `
    'quotation painter call'
}
$src=$src.Substring(0,$stateStart)+$state+$src.Substring($painterClass)

# painter section
$painterStart=$src.IndexOf("class _DigitalQuotationPainter")
$painter=$src.Substring($painterStart)
if($painter -notmatch "required this\.extraCosts"){
  $painter=Replace-Regex-One $painter `
    '(^\s*required this\.rates,\s*$)' `
    ('$1'+[Environment]::NewLine+'    required this.extraCosts,') `
    'quotation painter ctor'
}
if($painter -notmatch "final List<ExtraCostItem> extraCosts;"){
  $painter=Replace-Regex-One $painter `
    '(^\s*final ExchangeRateSettings rates;\s*$)' `
    ('$1'+[Environment]::NewLine+'  final List<ExtraCostItem> extraCosts;') `
    'quotation painter field'
}
if($painter -notmatch "final extraTotal = extraCosts\.fold"){
  $painter=Replace-Regex-One $painter `
    '(^\s*final usd = result\.totalUsd;\s*$)' `
    ('    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);'+[Environment]::NewLine+
     "    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');"+[Environment]::NewLine+
     '    final usd = result.totalUsd + extraTotal;') `
    'quotation total'
}
if($painter -match "_text\(c, '특별할인'.*sumTop \+ 34"){
  $pattern="(?ms)^\s*_text\(c, '특별할인', Rect\.fromLTWH\(totalX \+ 12, sumTop \+ 34, totalW \* \.46, adjH\), 16, bold: true\);\s*\r?\n\s*_text\(c, '-', Rect\.fromLTWH\(totalX \+ totalW \* \.52, sumTop \+ 34, totalW \* \.44, adjH\), 16, bold: true, right: true\);"
  $replacement="    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 (`$extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);"+[Environment]::NewLine+
               "    _text(c, extraTotal > 0 ? '+`$`{MoneyFormat.usd(extraTotal)}`' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);"
  $rx=[regex]::new($pattern)
  if($rx.Matches($painter).Count -ne 1){throw "안전 중단 [quotation extra row]: 대상=$($rx.Matches($painter).Count)"}
  $painter=$rx.Replace($painter,$replacement,1)
}
$src=$src.Substring(0,$painterStart)+$painter
Write-Utf8 $path $src

# ============================================================
# 2) statement_preview_dialog.dart
# ============================================================
$path="lib/screens/statement_preview_dialog.dart"
$src=Normalize-Literal-Newlines (Read-Utf8 $path)

if($src -notmatch "receipt_extra_cost_service\.dart"){
  $src=$src.Replace(
    "import '../services/customer_benefit_service.dart';",
    "import '../services/customer_benefit_service.dart';"+[Environment]::NewLine+"import '../services/receipt_extra_cost_service.dart';"
  )
}
if($src -notmatch "List<ExtraCostItem> _extraCosts"){
  $src=$src.Replace(
    "  String _inlandDeliveryText = '';",
    "  String _inlandDeliveryText = '';"+[Environment]::NewLine+"  List<ExtraCostItem> _extraCosts = const <ExtraCostItem>[];"
  )
}
if($src -notmatch "ReceiptExtraCostService\.instance\.list\(\s*\r?\n\s*route: widget\.routeLabel"){
  $pattern="(?ms)(\s*final inland = await CustomerBenefitService\.instance\s*\r?\n\s*\.inlandTextForRows\(widget\.routeLabel, rows\);)"
  $rx=[regex]::new($pattern)
  if($rx.Matches($src).Count -ne 1){throw "안전 중단 [statement load extra]: 대상=$($rx.Matches($src).Count)"}
  $replacement='$1'+[Environment]::NewLine+
"      final extraCosts = await ReceiptExtraCostService.instance.list("+[Environment]::NewLine+
"        route: widget.routeLabel,"+[Environment]::NewLine+
"        year: widget.year,"+[Environment]::NewLine+
"        voyage: widget.voyage,"+[Environment]::NewLine+
"        receiptNumber: widget.receiptNumber,"+[Environment]::NewLine+
"      );"
  $src=$rx.Replace($src,$replacement,1)
}
if($src -notmatch "_extraCosts = extraCosts;"){
  $src=Replace-Regex-One $src `
    '(^\s*_inlandDeliveryText = inland;\s*$)' `
    ('$1'+[Environment]::NewLine+'        _extraCosts = extraCosts;') `
    'statement set extra'
}

# UI painter call: first occurrence before painter class
$stateStart=$src.IndexOf("class _StatementPreviewDialogState")
$painterClass=$src.IndexOf("class _DigitalStatementPainter",$stateStart)
$state=$src.Substring($stateStart,$painterClass-$stateStart)
if($state -notmatch "extraCosts:\s*_extraCosts"){
  $state=Replace-Regex-One $state `
    '(^\s*inlandDeliveryText:\s*_inlandDeliveryText,\s*$)' `
    ('$1'+[Environment]::NewLine+'        extraCosts: _extraCosts,') `
    'statement painter call'
}
$src=$src.Substring(0,$stateStart)+$state+$src.Substring($painterClass)

# painter ctor + field
$painterStart=$src.IndexOf("class _DigitalStatementPainter")
$rendererStart=$src.IndexOf("class StatementDocumentRenderer",$painterStart)
if($rendererStart -lt 0){throw "안전 중단 [statement renderer class]"}
$painter=$src.Substring($painterStart,$rendererStart-$painterStart)
if($painter -notmatch "required this\.extraCosts"){
  $painter=Replace-Regex-One $painter `
    '(^\s*required this\.inlandDeliveryText,\s*$)' `
    ('$1'+[Environment]::NewLine+'    required this.extraCosts,') `
    'statement painter ctor'
}
if($painter -notmatch "final List<ExtraCostItem> extraCosts;"){
  $painter=Replace-Regex-One $painter `
    '(^\s*final String inlandDeliveryText;\s*$)' `
    ('$1'+[Environment]::NewLine+'  final List<ExtraCostItem> extraCosts;') `
    'statement painter field'
}
if($painter -notmatch "final finalUsd = freight\.totalUsd \+ extraTotal"){
  $painter=Replace-Regex-One $painter `
    '(^\s*final totalX = leftW \+ 6;\s*$)' `
    ('    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);'+[Environment]::NewLine+
     "    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');"+[Environment]::NewLine+
     '    final finalUsd = freight.totalUsd + extraTotal;'+[Environment]::NewLine+[Environment]::NewLine+
     '    final totalX = leftW + 6;') `
    'statement total vars'
}
if($painter -match "_text\(c, '특별할인'.*sumTop \+ 34"){
  $pattern="(?ms)^\s*_text\(c, '특별할인', Rect\.fromLTWH\(totalX \+ 12, sumTop \+ 34, totalW \* \.46, adjH\), 16, bold: true\);\s*\r?\n\s*_text\(c, '-', Rect\.fromLTWH\(totalX \+ totalW \* \.52, sumTop \+ 34, totalW \* \.44, adjH\), 16, bold: true, right: true\);"
  $replacement="    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 (`$extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);"+[Environment]::NewLine+
               "    _text(c, extraTotal > 0 ? '+`$`{MoneyFormat.usd(extraTotal)}`' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);"
  $rx=[regex]::new($pattern)
  if($rx.Matches($painter).Count -ne 1){throw "안전 중단 [statement extra row]: 대상=$($rx.Matches($painter).Count)"}
  $painter=$rx.Replace($painter,$replacement,1)
}
$painter=$painter.Replace("MoneyFormat.usd(freight.totalUsd)","MoneyFormat.usd(finalUsd)")
$painter=$painter.Replace("MoneyFormat.kip(freight.totalKip)","MoneyFormat.kip(finalUsd * freight.rates.appliedKip)")
$painter=$painter.Replace("MoneyFormat.thb(freight.totalThb)","MoneyFormat.thb(finalUsd * freight.rates.appliedThb)")
$painter=$painter.Replace("MoneyFormat.krw(freight.totalKrw)","MoneyFormat.krw(finalUsd * freight.rates.appliedKrw)")
$src=$src.Substring(0,$painterStart)+$painter+$src.Substring($rendererStart)

# batch renderer
$rendererStart=$src.IndexOf("class StatementDocumentRenderer")
$renderer=$src.Substring($rendererStart)
if($renderer -notmatch "ReceiptExtraCostService\.instance\.list\(\s*\r?\n\s*route: request\.routeLabel"){
  $idx=$renderer.IndexOf("    final painter = _DigitalStatementPainter(")
  if($idx -lt 0){throw "안전 중단 [statement batch painter]"}
  $insert=
"    final extraCosts = await ReceiptExtraCostService.instance.list("+[Environment]::NewLine+
"      route: request.routeLabel,"+[Environment]::NewLine+
"      year: request.year,"+[Environment]::NewLine+
"      voyage: request.voyage,"+[Environment]::NewLine+
"      receiptNumber: request.receiptNumber,"+[Environment]::NewLine+
"    );"+[Environment]::NewLine+[Environment]::NewLine
  $renderer=$renderer.Insert($idx,$insert)
}
if($renderer -notmatch "extraCosts:\s*extraCosts"){
  $renderer=Replace-Regex-One $renderer `
    '(^\s*inlandDeliveryText:\s*inland,\s*$)' `
    ('$1'+[Environment]::NewLine+'      extraCosts: extraCosts,') `
    'statement batch extra arg'
}
$src=$src.Substring(0,$rendererStart)+$renderer
Write-Utf8 $path $src

Write-Host "Patch143d 적용 완료"
Write-Host "이제 flutter analyze 실행"
