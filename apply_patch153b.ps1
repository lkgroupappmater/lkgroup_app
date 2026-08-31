$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

# IMPORTANT:
# Patch153은 아래 3개 파일까지 이미 저장된 뒤 quote 단계에서 중단되었습니다.
# - change_approval_screen.dart
# - cargo_management_screen.dart
# - shipment_search_screen.dart
# 따라서 이 스크립트는 그 파일들을 절대 건드리지 않습니다.

# ============================================================
# 1) quote_request_screen.dart
# ============================================================
$p="lib/screens/quote_request_screen.dart"
$t=ReadText $p

# _freightResultCard 함수 범위만 수정
$startToken="  Widget _freightResultCard(QuoteFreightResult result) {"
$endToken="  Widget _specialQuoteCard(Map<String, dynamic> quote) {"
$s=$t.IndexOf($startToken)
$e=$t.IndexOf($endToken)
if ($s -lt 0 -or $e -le $s) { throw "안전 중단 [quote freight function range]" }
$before=$t.Substring(0,$s)
$section=$t.Substring($s,$e-$s)
$after=$t.Substring($e)

$section=ReplaceOnce $section @'
  Widget _freightResultCard(QuoteFreightResult result) {
    final rates = _calculationRates;
    final kip = rates == null ? null : result.totalUsd * rates.appliedKip;
    final thb = rates == null ? null : result.totalUsd * rates.appliedThb;
    final krw = rates == null ? null : result.totalUsd * rates.appliedKrw;
'@ @'
  Widget _freightResultCard(QuoteFreightResult result) {
    final rates = _calculationRates;
    final extraTotal =
        _extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final finalUsd = result.totalUsd + extraTotal;
    final kip = rates == null ? null : finalUsd * rates.appliedKip;
    final thb = rates == null ? null : finalUsd * rates.appliedThb;
    final krw = rates == null ? null : finalUsd * rates.appliedKrw;
'@ "quote totals"

$section=ReplaceOnce $section @'
            const Divider(),
            Align(
'@ @'
            if (_extraCosts.isNotEmpty) ...[
              const Divider(),
              ..._extraCosts.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '기타 비용 · ${e.name}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '+\$${e.amountUsd.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(),
            Align(
'@ "quote extra rows"

# 함수 범위 안에서 총 운임 숫자만 정확히 바꿈
$section=ReplaceOnce $section "result.totalUsd.toStringAsFixed(2)" "finalUsd.toStringAsFixed(2)" "quote usd display"

$t=$before+$section+$after
WriteText $p $t

# ============================================================
# 2) quotation_preview_dialog.dart
# ============================================================
$p="lib/screens/quotation_preview_dialog.dart"
$t=ReadText $p

$t=ReplaceOnce $t "  int get _visibleRows => widget.boxes.length + 1 < 10 ? 10 : widget.boxes.length + 1;" "  int get _visibleRows => widget.boxes.length + widget.extraCosts.length + 1 < 10`n      ? 10`n      : widget.boxes.length + widget.extraCosts.length + 1;" "quotation visible rows"

$t=ReplaceOnce $t "    final rowCount = boxes.length + 1 < 10 ? 10 : boxes.length + 1;" "    final usedRows = boxes.length + extraCosts.length;`n    final rowCount = usedRows + 1 < 10 ? 10 : usedRows + 1;" "quotation row count"

$t=ReplaceOnce $t @'
      final has = i < boxes.length;
      final b = has ? boxes[i] : null;
'@ @'
      final has = i < boxes.length;
      final extraIndex = i - boxes.length;
      final hasExtra = extraIndex >= 0 && extraIndex < extraCosts.length;
      final b = has ? boxes[i] : null;
'@ "quotation extra index"

$t=ReplaceOnce $t @'
      if (!has || b == null) continue;

      final qty = b.quantity < 1 ? 1 : b.quantity;
'@ @'
      if (hasExtra) {
        final extra = extraCosts[extraIndex];
        _text(
          c,
          extra.name,
          Rect.fromLTRB(cols[1] + 3, y + 2, cols[2] - 3, y + rowH - 2),
          17,
          bold: true,
          center: true,
        );
        _text(
          c,
          MoneyFormat.usd(extra.amountUsd),
          Rect.fromLTRB(cols[13] + 3, y + 2, cols[14] - 3, y + rowH - 2),
          20,
          bold: true,
          right: true,
        );
        continue;
      }
      if (!has || b == null) continue;

      final qty = b.quantity < 1 ? 1 : b.quantity;
'@ "quotation extra draw"

$t=ReplaceOnce $t @'
    final totalVolume = boxes.fold<double>(0, (v, b) => v + b.result.volumeWeightKg);
    final summaryValues = <int, String>{
'@ @'
    final totalVolume = boxes.fold<double>(0, (v, b) => v + b.result.volumeWeightKg);
    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final usd = result.totalUsd + extraTotal;
    final summaryValues = <int, String>{
'@ "quotation summary totals"

$t=ReplaceOnce $t "      13: MoneyFormat.usd(result.totalUsd)," "      13: MoneyFormat.usd(usd)," "quotation summary usd"

$t=ReplaceOnce $t @'
    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');
    final usd = result.totalUsd + extraTotal;
'@ @'
    final extraNames =
        extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');
'@ "quotation duplicate totals"

WriteText $p $t

# ============================================================
# 3) statement_preview_dialog.dart
# ============================================================
$p="lib/screens/statement_preview_dialog.dart"
$t=ReadText $p

$t=ReplaceOnce $t "  int get _visibleRows => _rows.length + 1 < 10 ? 10 : _rows.length + 1;" "  int get _visibleRows => _rows.length + _extraCosts.length + 1 < 10`n      ? 10`n      : _rows.length + _extraCosts.length + 1;" "statement visible rows"

$t=ReplaceOnce $t "    final rowCount = rows.length + 1 < 10 ? 10 : rows.length + 1;" "    final usedRows = rows.length + extraCosts.length;`n    final rowCount = usedRows + 1 < 10 ? 10 : usedRows + 1;" "statement row count"

$t=ReplaceOnce $t @'
      final has = i < rows.length;
      final row = has ? rows[i] : const <String, dynamic>{};
'@ @'
      final has = i < rows.length;
      final extraIndex = i - rows.length;
      final hasExtra = extraIndex >= 0 && extraIndex < extraCosts.length;
      final row = has ? rows[i] : const <String, dynamic>{};
'@ "statement extra index"

$t=ReplaceOnce $t @'
      if (!has) continue;
      final qty = _d(row['quantity'], 1).clamp(1, 999999).toDouble();
'@ @'
      if (hasExtra) {
        final extra = extraCosts[extraIndex];
        _text(
          c,
          extra.name,
          Rect.fromLTRB(cols[1] + 3, y + 2, cols[2] - 3, y + rowH - 2),
          17,
          bold: true,
          center: true,
        );
        _text(
          c,
          MoneyFormat.usd(extra.amountUsd),
          Rect.fromLTRB(cols[13] + 3, y + 2, cols[14] - 3, y + rowH - 2),
          20,
          bold: true,
          right: true,
        );
        continue;
      }
      if (!has) continue;
      final qty = _d(row['quantity'], 1).clamp(1, 999999).toDouble();
'@ "statement extra draw"

WriteText $p $t

Write-Host ""
Write-Host "Patch153b 적용 완료"
Write-Host "- Patch153 앞부분은 재실행하지 않음"
Write-Host "- quote_request_screen.dart 기타비용 최종 운임 반영"
Write-Host "- quotation_preview_dialog.dart 기타비용 표 행 반영"
Write-Host "- statement_preview_dialog.dart 기타비용 표 행 반영"
Write-Host ""
Write-Host "다음: flutter analyze"
