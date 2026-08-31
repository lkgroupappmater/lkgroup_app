$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

# ============================================================
# 1) change_approval_screen.dart
# ============================================================
$p="lib/screens/change_approval_screen.dart"
$t=ReadText $p

# 중간 잠금 문구 제거 (우측 상단 배지만 유지)
$t=ReplaceOnce $t @'
            if (r['data_locked'] == true) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.lock, size: 16, color: Colors.redAccent),
                  SizedBox(width: 5),
                  Text(
                    '🔒 현재 잠금 상태',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
'@ "" "remove duplicate request lock text"

# 요청내용 표시 호출 개선
$t=ReplaceOnce $t "            Text(_changesText(requested))," "            Text(_changesText(requested, r))," "changes call"

# 변경내용 formatter 교체
$start="  String _changesText(Map<String, dynamic> changes) {"
$idx=$t.IndexOf($start)
if ($idx -lt 0) { throw "안전 중단 [changes formatter]: 시작점 없음" }
$end=$t.IndexOf("`n  }", $idx)
if ($end -lt 0) { throw "안전 중단 [changes formatter]: 끝점 없음" }
$end=$end+4
$new=@'
  String _changesText(
    Map<String, dynamic> changes,
    Map<String, dynamic> current,
  ) {
    if (changes.isEmpty) return '변경 내용 없음';
    const labels = {
      'consignee_name': '이름/수령인',
      'consignee_phone': '연락처',
      'notes': '기타 내용',
      'invoice_number': '송장번호',
      'weight_kg': '무게',
      'length_cm': '가로',
      'width_cm': '세로',
      'height_cm': '높이',
      'received_at': '요청 일시',
    };

    String clean(dynamic value) {
      final text = '${value ?? ''}'.trim();
      if (text.isEmpty) return '-';
      final parsed = DateTime.tryParse(text);
      if (parsed != null) {
        final local = parsed.toLocal();
        String two(int v) => v.toString().padLeft(2, '0');
        return '${local.year}-${two(local.month)}-${two(local.day)} '
            '${two(local.hour)}:${two(local.minute)}';
      }
      return text;
    }

    return changes.entries.map((e) {
      final label = labels[e.key] ?? e.key;
      if (e.key == 'received_at') {
        return '$label: ${clean(e.value)}';
      }
      final before = clean(current[e.key]);
      final after = clean(e.value);
      return '$label: $before → $after';
    }).join('\n');
  }
'@
$t=$t.Substring(0,$idx)+$new+$t.Substring($end)
WriteText $p $t

# ============================================================
# 2) cargo_management_screen.dart : 영수번호 헤더 강조 구분
# ============================================================
$p="lib/screens/cargo_management_screen.dart"
$t=ReadText $p
$t=ReplaceOnce $t @'
                      Text(
                        '영수번호/구획: ${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text(
                        '총 개수: $totalQty개',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
'@ @'
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '영수번호/구획: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: receipt.isEmpty ? '-' : receipt,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                            const TextSpan(
                              text: ' / ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: zone.isEmpty ? '-' : zone,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '총 개수: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: '$totalQty개',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
'@ "cargo receipt emphasis"
WriteText $p $t

# ============================================================
# 3) shipment_search_screen.dart : 화물관리와 같은 항차>영수번호>화물 구조
# ============================================================
$p="lib/screens/shipment_search_screen.dart"
$t=ReadText $p
$start="  List<Widget> _groupedResultWidgets() {"
$end="  String _weightOneDecimal(dynamic value) {"
$s=$t.IndexOf($start)
$e=$t.IndexOf($end)
if ($s -lt 0 -or $e -le $s) { throw "안전 중단 [shipment grouped section]" }

$new=@'
  List<MapEntry<String, List<Map<String, dynamic>>>> _receiptGroups(
    List<Map<String, dynamic>> rows,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      map.putIfAbsent(receipt, () => <Map<String, dynamic>>[]).add(row);
    }
    final entries = map.entries.toList();
    int tailNumber(String value) {
      final m = RegExp(r'(\d+)\s*$').firstMatch(value);
      return m == null ? 999999 : int.tryParse(m.group(1)!) ?? 999999;
    }
    entries.sort((a, b) {
      final an = tailNumber(a.key);
      final bn = tailNumber(b.key);
      if (an != bn) return an.compareTo(bn);
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  void _toggleReceiptGroup(List<Map<String, dynamic>> rows) {
    final ids = rows.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  List<Widget> _groupedResultWidgets() {
    return _resultGroups().map((entry) {
      final rows = entry.value;
      final first = rows.first;
      final ids = rows.map((r) => '${r['id']}').toSet();
      final all = ids.isNotEmpty && _selectedIds.containsAll(ids);
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              color: AppColors.inputFill,
              child: Row(
                children: [
                  Checkbox(
                    value: all,
                    onChanged: (_) => _toggleGroup(rows),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      '${first['route']} · ${first['shipment_year']}년도 · ${_voyageLabel(first['voyage'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showGroupFreight(rows),
                    icon: const Icon(Icons.price_check_outlined, size: 17),
                    label: const Text('운임'),
                  ),
                ],
              ),
            ),
            ..._receiptGroups(rows).map((e) => _receiptResultCard(e.value)),
          ],
        ),
      );
    }).toList();
  }

  Widget _receiptResultCard(List<Map<String, dynamic>> rows) {
    final first = rows.first;
    final ids = rows.map((r) => '${r['id']}').toSet();
    final all = ids.isNotEmpty && _selectedIds.containsAll(ids);
    final receipt = '${first['receipt_number'] ?? ''}'.trim();
    final zone = '${first['unloading_zone'] ?? ''}'.trim();
    final name = '${first['consignee_name'] ?? ''}'.trim();
    final company = _companyOf(first);
    final phone = '${first['consignee_phone'] ?? ''}'.trim();
    final totalQty = rows.fold<int>(
      0,
      (sum, r) => sum + (int.tryParse('${r['quantity'] ?? ''}') ?? 1),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD7DEE7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: all,
                  onChanged: (_) => _toggleReceiptGroup(rows),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$name / ${company.isEmpty ? '-' : company}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text(
                        phone.isEmpty ? '-' : phone,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                            text: '영수번호/구획: ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: receipt.isEmpty ? '-' : receipt,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyPrimary,
                            ),
                          ),
                          const TextSpan(
                            text: ' / ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: _showZone ? (zone.isEmpty ? '-' : zone) : '-',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyPrimary,
                            ),
                          ),
                        ]),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                            text: '총 개수: ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: '$totalQty개',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyPrimary,
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...rows.map(_shipmentCard),
        ],
      ),
    );
  }

  Widget _shipmentCard(Map<String, dynamic> r) {
    final id = '${r['id']}';
    final quantity = int.tryParse('${r['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(r['received_at']);
    final length = _naturalNumber(r['length_cm']);
    final height = _naturalNumber(r['height_cm']);
    final width = _naturalNumber(r['width_cm']);
    final size = '$length × $height × $width cm';

    return InkWell(
      onTap: () => _toggle(id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _selectedIds.contains(id),
              onChanged: (_) => _toggle(id),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('화물번호', '${r['box_number'] ?? ''}'),
                  _row('송장번호', '${r['invoice_number'] ?? ''}'),
                  _row('화물개수', '$quantity개'),
                  _row(
                    '무게 / 크기',
                    '${_weightOneDecimal(r['weight_kg'])} kg / $size',
                  ),
                  _row('입고날짜', receivedDate),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

'@
$t=$t.Substring(0,$s)+$new+$t.Substring($e)
WriteText $p $t

# ============================================================
# 4) quote_request_screen.dart : 운임확인 카드에 기타비용 실제 합산/표시
# ============================================================
$p="lib/screens/quote_request_screen.dart"
$t=ReadText $p
$t=ReplaceOnce $t @'
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
'@ "quote freight total"

$t=ReplaceOnce $t @'
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

$t=ReplaceOnce $t "'총 운임  USD \\$${result.totalUsd.toStringAsFixed(2)}'" "'최종 운임  USD \\$${finalUsd.toStringAsFixed(2)}'" "quote final label"
WriteText $p $t

# ============================================================
# 5) quotation_preview_dialog.dart : 기타비용을 표 마지막 행에 직접 기입
# ============================================================
$p="lib/screens/quotation_preview_dialog.dart"
$t=ReadText $p
$t=ReplaceOnce $t "  int get _visibleRows => widget.boxes.length + 1 < 10 ? 10 : widget.boxes.length + 1;" "  int get _visibleRows => widget.boxes.length + widget.extraCosts.length + 1 < 10`n      ? 10`n      : widget.boxes.length + widget.extraCosts.length + 1;" "quotation visible rows"

$t=ReplaceOnce $t "    final rowCount = boxes.length + 1 < 10 ? 10 : boxes.length + 1;" "    final usedRows = boxes.length + extraCosts.length;`n    final rowCount = usedRows + 1 < 10 ? 10 : usedRows + 1;" "quotation row count"

# loop의 has 분기 확장
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

# summary에서 총액에 extra 포함
$t=ReplaceOnce $t @'
    final totalVolume = boxes.fold<double>(0, (v, b) => v + b.result.volumeWeightKg);
    final summaryValues = <int, String>{
'@ @'
    final totalVolume = boxes.fold<double>(0, (v, b) => v + b.result.volumeWeightKg);
    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final usd = result.totalUsd + extraTotal;
    final summaryValues = <int, String>{
'@ "quotation summary extra"

$t=ReplaceOnce $t "      13: MoneyFormat.usd(result.totalUsd)," "      13: MoneyFormat.usd(usd)," "quotation summary final"

# 후반 중복 extraTotal/usd 선언 제거
$t=ReplaceOnce $t @'
    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');
    final usd = result.totalUsd + extraTotal;
'@ @'
    final extraNames =
        extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');
'@ "quotation remove duplicate totals"
WriteText $p $t

# ============================================================
# 6) statement_preview_dialog.dart : 기타비용 표 마지막 행 + 합계
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
Write-Host "Patch153 적용 완료"
Write-Host "- 변경승인: 중복 잠금표시 제거 / received_at -> 요청 일시 / 이전값 -> 요청값"
Write-Host "- 화물관리 영수번호 헤더 강조 구분"
Write-Host "- 화물조회도 항차 > 영수번호 > 화물 그룹 구조"
Write-Host "- 운임확인 가견적에 기타비용 합산 표시"
Write-Host "- 가견적서/명세서 표 마지막 행에 기타비용 이름/금액 직접 표시"
Write-Host ""
Write-Host "다음: flutter analyze"
