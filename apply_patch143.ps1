$ErrorActionPreference = "Stop"

function Replace-Once([string]$src,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($src,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $src.Replace($old,$new)
}

# ------------------------------------------------------------
# 1) cargo_management_screen.dart
# ------------------------------------------------------------
$path = "lib/screens/cargo_management_screen.dart"
$src = Get-Content $path -Raw -Encoding UTF8

$src = Replace-Once $src `
  "import '../services/shipment_filter_options_service.dart';" `
  "import '../services/shipment_filter_options_service.dart';`r`nimport '../services/receipt_extra_cost_service.dart';" `
  "cargo import"

$start = $src.IndexOf("  List<Widget> _managementGroupWidgets() {")
$end = $src.IndexOf("  Widget _shipmentCard(Map<String, dynamic> item) {")
if ($start -lt 0 -or $end -le $start) { throw "안전 중단 [cargo receipt grouping]: 함수 범위를 찾지 못했습니다." }

$newBlock = @'
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

  Future<void> _showReceiptExtraCostDialog(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty || !(_isAdmin || _isStaff)) return;
    final first = rows.first;
    final route = '${first['route'] ?? ''}'.trim();
    final year = (first['shipment_year'] as num?)?.toInt();
    final voyage = '${first['voyage'] ?? ''}'.trim();
    final receipt = '${first['receipt_number'] ?? ''}'.trim();
    if (route.isEmpty || year == null || voyage.isEmpty || receipt.isEmpty) {
      _message('기타 비용을 연결할 영수번호 정보를 확인할 수 없습니다.');
      return;
    }

    final name = TextEditingController();
    final amount = TextEditingController();
    int? editingId;
    var items = await ReceiptExtraCostService.instance.list(
      route: route,
      year: year,
      voyage: voyage,
      receiptNumber: receipt,
    );
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> reload() async {
            final next = await ReceiptExtraCostService.instance.list(
              route: route,
              year: year,
              voyage: voyage,
              receiptNumber: receipt,
            );
            if (dialogContext.mounted) setDialogState(() => items = next);
          }

          return AlertDialog(
            title: Text('$receipt · 기타 비용 (+$)'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (items.isNotEmpty) ...[
                      ...items.map(
                        (e) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.name),
                          subtitle: Text('\$${e.amountUsd.toStringAsFixed(2)}'),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: '수정',
                                onPressed: () {
                                  setDialogState(() => editingId = e.id);
                                  name.text = e.name;
                                  amount.text = e.amountUsd.toStringAsFixed(2);
                                },
                                icon: const Icon(Icons.edit_outlined, size: 19),
                              ),
                              IconButton(
                                tooltip: '삭제',
                                onPressed: e.id == null
                                    ? null
                                    : () async {
                                        await ReceiptExtraCostService.instance
                                            .delete(e.id!);
                                        await reload();
                                      },
                                icon: const Icon(Icons.delete_outline, size: 19),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(),
                    ],
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '비용 이름',
                        hintText: '예: 통관비용, 보관료',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '금액 (USD)',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('닫기'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final value = double.tryParse(amount.text.trim());
                  if (name.text.trim().isEmpty || value == null || value < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('비용 이름과 금액을 확인해 주세요.')),
                    );
                    return;
                  }
                  await ReceiptExtraCostService.instance.save(
                    id: editingId,
                    route: route,
                    year: year,
                    voyage: voyage,
                    receiptNumber: receipt,
                    name: name.text,
                    amountUsd: value,
                  );
                  name.clear();
                  amount.clear();
                  setDialogState(() => editingId = null);
                  await reload();
                },
                icon: const Icon(Icons.add_card_outlined, size: 18),
                label: Text(editingId == null ? '추가' : '수정 저장'),
              ),
            ],
          );
        },
      ),
    );
    name.dispose();
    amount.dispose();
  }

  List<Widget> _managementGroupWidgets() {
    return _managementGroups().map((entry) {
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
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              color: AppColors.inputFill,
              child: Row(
                children: [
                  Checkbox(
                    value: all,
                    onChanged: (_) => _toggleManagementGroup(rows),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      '${first['route']} · ${first['shipment_year']}년도 · ${_voyageLabel(first['voyage'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_isManager)
                    IconButton(
                      tooltip: '선택 화물 편집',
                      onPressed: _busy ? null : () => _editCheckedGroup(rows),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                  if (_isManager)
                    IconButton(
                      tooltip: '선택 화물 삭제',
                      onPressed: _busy ? null : () => _deleteCheckedGroup(rows),
                      icon: const Icon(Icons.delete_outline, size: 19),
                    ),
                ],
              ),
            ),
            ..._receiptGroups(rows).map((e) => _receiptGroupCard(e.value)),
          ],
        ),
      );
    }).toList();
  }

  Widget _receiptGroupCard(List<Map<String, dynamic>> rows) {
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
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '이름/회사명: $name / ${company.isEmpty ? '-' : company}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text('연락처: ${phone.isEmpty ? '-' : phone}',
                          style: const TextStyle(fontSize: 12)),
                      Text(
                        '영수번호/구획: ${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text('총 개수: $totalQty개',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  IconButton(
                    tooltip: '기타 비용 (+$)',
                    onPressed:
                        _busy ? null : () => _showReceiptExtraCostDialog(rows),
                    icon: const Icon(Icons.add_card_outlined, size: 21),
                  ),
              ],
            ),
          ),
          ...rows.map(_receiptShipmentCard),
        ],
      ),
    );
  }

  Widget _receiptShipmentCard(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final quantity = int.tryParse('${item['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(item['received_at']);
    final length = _naturalNumber(item['length_cm']);
    final height = _naturalNumber(item['height_cm']);
    final width = _naturalNumber(item['width_cm']);
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
                  _infoRow('화물번호', '${item['box_number'] ?? ''}'),
                  _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
                  _infoRow('화물개수', '$quantity개'),
                  _infoRow(
                    '무게 / 크기',
                    '${_weightOneDecimal(item['weight_kg'])} kg / $size',
                  ),
                  _infoRow('입고날짜', receivedDate),
                  if (_isManager) ...[
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 12,
                        children: [
                          IconButton(
                            tooltip: '편집',
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() {
                                      _selectedIds
                                        ..clear()
                                        ..add(id);
                                    });
                                    await _editCheckedGroup([item]);
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                          if (_isAdmin)
                            IconButton(
                              tooltip:
                                  item['data_locked'] == true ? '잠금 해제' : '잠금',
                              visualDensity: VisualDensity.compact,
                              onPressed: _busy
                                  ? null
                                  : () => _toggleShipmentLock(item),
                              icon: Icon(
                                item['data_locked'] == true
                                    ? Icons.lock
                                    : Icons.lock_open_outlined,
                                size: 19,
                                color: item['data_locked'] == true
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
'@

$src = $src.Substring(0,$start) + $newBlock + "`r`n" + $src.Substring($end)
Set-Content $path $src -Encoding UTF8

# ------------------------------------------------------------
# 2) quote_request_screen.dart : 견적용 로컬 기타비용
# ------------------------------------------------------------
$path = "lib/screens/quote_request_screen.dart"
$src = Get-Content $path -Raw -Encoding UTF8
$src = Replace-Once $src `
  "import '../services/quote_service.dart';" `
  "import '../services/quote_service.dart';`r`nimport '../services/receipt_extra_cost_service.dart';" `
  "quote import"

$src = Replace-Once $src `
  "  final List<_BoxEntry> _boxes = [_BoxEntry()];" `
  "  final List<_BoxEntry> _boxes = [_BoxEntry()];`r`n  final List<ExtraCostItem> _extraCosts = <ExtraCostItem>[];" `
  "quote state"

$anchor = "  void _removeBox(int i) {"
$method = @'
  Future<void> _addQuoteExtraCost() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final save = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('기타 비용 추가 (+$)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: '비용 이름',
                    hintText: '예: 통관비용, 기타 수수료',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '금액 (USD)',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('추가'),
              ),
            ],
          ),
        ) ??
        false;
    if (save) {
      final value = double.tryParse(amount.text.trim());
      if (name.text.trim().isEmpty || value == null || value < 0) {
        _message('비용 이름과 금액을 확인해 주세요.');
      } else {
        setState(() {
          _extraCosts.add(
            ExtraCostItem(name: name.text.trim(), amountUsd: value),
          );
        });
      }
    }
    name.dispose();
    amount.dispose();
  }

  void _removeBox(int i) {
'@
$src = Replace-Once $src $anchor $method "quote extra method"

$src = Replace-Once $src `
  "        rates: rates,`r`n      )," `
  "        rates: rates,`r`n        extraCosts: List<ExtraCostItem>.unmodifiable(_extraCosts),`r`n      )," `
  "quote preview args"

# 박스 추가 버튼 직후: 다음 큰 여백 전에 기타비용 버튼/목록 삽입
$needle = "            label: const Text('박스 추가', style: TextStyle(fontSize: 13)),"
$idx = $src.IndexOf($needle)
if ($idx -lt 0) { throw "안전 중단 [quote button]: 박스 추가 버튼을 찾지 못했습니다." }
$styleEnd = $src.IndexOf("          ),", $idx)
$styleEnd = $src.IndexOf("          ),", $styleEnd + 1)
if ($styleEnd -lt 0) { throw "안전 중단 [quote button]: 버튼 끝 위치를 찾지 못했습니다." }
$insertPos = $styleEnd + "          ),".Length
$insert = @'

          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addQuoteExtraCost,
            icon: const Icon(Icons.add_card_outlined, size: 18),
            label: const Text('기타 비용 추가 (+$)',
                style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navyPrimary,
              side: const BorderSide(color: AppColors.navyPrimary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          if (_extraCosts.isNotEmpty) ...[
            const SizedBox(height: 6),
            ..._extraCosts.asMap().entries.map(
              (entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('\$${entry.value.amountUsd.toStringAsFixed(2)}'),
                    IconButton(
                      tooltip: '삭제',
                      onPressed: () =>
                          setState(() => _extraCosts.removeAt(entry.key)),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
'@
$src = $src.Insert($insertPos,$insert)
Set-Content $path $src -Encoding UTF8

# ------------------------------------------------------------
# 3) quotation_preview_dialog.dart
# ------------------------------------------------------------
$path = "lib/screens/quotation_preview_dialog.dart"
$src = Get-Content $path -Raw -Encoding UTF8
$src = Replace-Once $src `
  "import '../services/quote_freight_calculator.dart';" `
  "import '../services/quote_freight_calculator.dart';`r`nimport '../services/receipt_extra_cost_service.dart';" `
  "quotation import"

$src = Replace-Once $src `
  "    required this.rates,`r`n  });" `
  "    required this.rates,`r`n    this.extraCosts = const <ExtraCostItem>[],`r`n  });" `
  "quotation ctor"

$src = Replace-Once $src `
  "  final ExchangeRateSettings rates;" `
  "  final ExchangeRateSettings rates;`r`n  final List<ExtraCostItem> extraCosts;" `
  "quotation field"

$src = Replace-Once $src `
  "        rates: widget.rates,`r`n        issuedAt: _issuedAt," `
  "        rates: widget.rates,`r`n        extraCosts: widget.extraCosts,`r`n        issuedAt: _issuedAt," `
  "quotation painter call"

$src = Replace-Once $src `
  "    required this.rates,`r`n    required this.issuedAt," `
  "    required this.rates,`r`n    required this.extraCosts,`r`n    required this.issuedAt," `
  "quotation painter ctor"

$src = Replace-Once $src `
  "  final ExchangeRateSettings rates;`r`n  final DateTime issuedAt;" `
  "  final ExchangeRateSettings rates;`r`n  final List<ExtraCostItem> extraCosts;`r`n  final DateTime issuedAt;" `
  "quotation painter field"

$src = Replace-Once $src `
  "    final usd = result.totalUsd;" `
  "    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);`r`n    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');`r`n    final usd = result.totalUsd + extraTotal;" `
  "quotation final total"

$oldAdj = @'
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@
$newAdj = @'
    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 ($extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, extraTotal > 0 ? '+${MoneyFormat.usd(extraTotal)}' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@
$src = Replace-Once $src $oldAdj $newAdj "quotation extra row"
Set-Content $path $src -Encoding UTF8

# ------------------------------------------------------------
# 4) statement_preview_dialog.dart
# ------------------------------------------------------------
$path = "lib/screens/statement_preview_dialog.dart"
$src = Get-Content $path -Raw -Encoding UTF8
$src = Replace-Once $src `
  "import '../services/customer_benefit_service.dart';" `
  "import '../services/customer_benefit_service.dart';`r`nimport '../services/receipt_extra_cost_service.dart';" `
  "statement import"

$src = Replace-Once $src `
  "  String _inlandDeliveryText = '';" `
  "  String _inlandDeliveryText = '';`r`n  List<ExtraCostItem> _extraCosts = const <ExtraCostItem>[];" `
  "statement state"

$src = Replace-Once $src `
  "      final inland = await CustomerBenefitService.instance`r`n          .inlandTextForRows(widget.routeLabel, rows);" `
  "      final inland = await CustomerBenefitService.instance`r`n          .inlandTextForRows(widget.routeLabel, rows);`r`n      final extraCosts = await ReceiptExtraCostService.instance.list(`r`n        route: widget.routeLabel,`r`n        year: widget.year,`r`n        voyage: widget.voyage,`r`n        receiptNumber: widget.receiptNumber,`r`n      );" `
  "statement load extra"

$src = Replace-Once $src `
  "        _inlandDeliveryText = inland;`r`n        _loading = false;" `
  "        _inlandDeliveryText = inland;`r`n        _extraCosts = extraCosts;`r`n        _loading = false;" `
  "statement set extra"

$src = Replace-Once $src `
  "        inlandDeliveryText: _inlandDeliveryText,`r`n        logo: _logo!," `
  "        inlandDeliveryText: _inlandDeliveryText,`r`n        extraCosts: _extraCosts,`r`n        logo: _logo!," `
  "statement painter call"

$src = Replace-Once $src `
  "    required this.inlandDeliveryText,`r`n    required this.logo," `
  "    required this.inlandDeliveryText,`r`n    required this.extraCosts,`r`n    required this.logo," `
  "statement painter ctor"

$src = Replace-Once $src `
  "  final String inlandDeliveryText;`r`n  final ui.Image logo;" `
  "  final String inlandDeliveryText;`r`n  final List<ExtraCostItem> extraCosts;`r`n  final ui.Image logo;" `
  "statement painter field"

# 배치 PDF renderer에서도 비용 로드 + painter 전달
$batchAnchor = "    final painter = _DigitalStatementPainter("
$batchIdx = $src.LastIndexOf($batchAnchor)
if ($batchIdx -lt 0) { throw "안전 중단 [statement batch painter]: 찾지 못했습니다." }
$loadAnchor = "    final painter = _DigitalStatementPainter("
$insertBatch = @'
    final extraCosts = await ReceiptExtraCostService.instance.list(
      route: request.routeLabel,
      year: request.year,
      voyage: request.voyage,
      receiptNumber: request.receiptNumber,
    );

'@
$src = $src.Insert($batchIdx,$insertBatch)
# 마지막 painter 호출에서 inlandDeliveryText 다음에 extraCosts
$beforeLast = $src.Substring(0,$batchIdx + $insertBatch.Length)
$afterLast = $src.Substring($batchIdx + $insertBatch.Length)
$afterLast = Replace-Once $afterLast `
  "      inlandDeliveryText: inland,`r`n      logo: assets[0]," `
  "      inlandDeliveryText: inland,`r`n      extraCosts: extraCosts,`r`n      logo: assets[0]," `
  "statement batch extra arg"
$src = $beforeLast + $afterLast

# painter 금액부
$marker = "    final totalX = leftW + 6;"
$firstTotal = $src.IndexOf($marker)
if ($firstTotal -lt 0) { throw "안전 중단 [statement total]: 합계 영역 없음" }
$insertPos = $firstTotal
$src = $src.Insert($insertPos, "    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);`r`n    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');`r`n    final finalUsd = freight.totalUsd + extraTotal;`r`n")

$oldAdj = @'
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@
$newAdj = @'
    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 ($extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, extraTotal > 0 ? '+${MoneyFormat.usd(extraTotal)}' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@
$src = Replace-Once $src $oldAdj $newAdj "statement extra row"

$src = Replace-Once $src `
  "    _text(c, 'USD    ' + MoneyFormat.usd(freight.totalUsd)," `
  "    _text(c, 'USD    ' + MoneyFormat.usd(finalUsd)," `
  "statement usd final"
$src = Replace-Once $src `
  "    _text(c, 'KIP    ' + MoneyFormat.kip(freight.totalKip)," `
  "    _text(c, 'KIP    ' + MoneyFormat.kip(finalUsd * freight.rates.appliedKip)," `
  "statement kip final"
$src = Replace-Once $src `
  "    _text(c, 'THB    ' + MoneyFormat.thb(freight.totalThb)," `
  "    _text(c, 'THB    ' + MoneyFormat.thb(finalUsd * freight.rates.appliedThb)," `
  "statement thb final"
$src = Replace-Once $src `
  "    _text(c, 'KRW    ' + MoneyFormat.krw(freight.totalKrw)," `
  "    _text(c, 'KRW    ' + MoneyFormat.krw(finalUsd * freight.rates.appliedKrw)," `
  "statement krw final"

Set-Content $path $src -Encoding UTF8

Write-Host "Patch143 Flutter 적용 완료"
Write-Host "다음: supabase/089_receipt_extra_costs.sql 실행 -> flutter analyze -> flutter run"
