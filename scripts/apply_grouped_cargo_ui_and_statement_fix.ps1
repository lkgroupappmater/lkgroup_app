$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

function Read-Utf8($path) { Get-Content $path -Raw -Encoding UTF8 }
function Write-Utf8($path,$text) { Set-Content $path $text -Encoding UTF8 }

# ------------------------------------------------------------------
# 1) 화물 조회: 전체 경로 + 그룹 UI
# ------------------------------------------------------------------
$searchPath = Join-Path $project 'lib/screens/shipment_search_screen.dart'
$s = Read-Utf8 $searchPath

$s = $s.Replace("  int _selectedRoute = 0;", "  int _selectedRoute = -1;")
$s = $s.Replace(
"  bool get _showZone => widget.currentUser?.role == UserRole.admin || widget.currentUser?.role == UserRole.staff;",
"  bool get _showZone => widget.currentUser?.role == UserRole.admin || widget.currentUser?.role == UserRole.staff;`r`n  String get _selectedRouteLabel => _selectedRoute < 0 ? '전체' : routeLabels[_selectedRoute];"
)

$s = $s.Replace(
"    final route = routeLabels[_selectedRoute];`r`n    final years =`r`n        ShipmentFilterOptionsService.instance.yearsFor(_filterBatches, route);",
"    final route = _selectedRouteLabel;`r`n    final years = route == '전체'`r`n        ? (_filterBatches.map((e) => e.year).toSet().toList()..sort((a,b) => b.compareTo(a)))`r`n        : ShipmentFilterOptionsService.instance.yearsFor(_filterBatches, route);"
)
$s = $s.Replace(
"    final route = routeLabels[_selectedRoute];",
"    final route = _selectedRouteLabel;"
)
$s = $s.Replace(
"    final voyages = ShipmentFilterOptionsService.instance`r`n        .voyagesFor(_filterBatches, route, year);",
"    final voyages = route == '전체'`r`n        ? (_filterBatches.where((e) => e.year == year).map((e) => e.voyage).toSet().toList())`r`n        : ShipmentFilterOptionsService.instance.voyagesFor(_filterBatches, route, year);"
)
$s = $s.Replace(
"        route: routeLabels[_selectedRoute],",
"        route: _selectedRouteLabel,"
)

$oldItems = @"
            items: List.generate(
              routeLabels.length,
              (index) => DropdownMenuItem(
                value: index,
                child: Text(routeLabels[index]),
              ),
            ),
"@
$newItems = @"
            items: <DropdownMenuItem<int>>[
              const DropdownMenuItem(value: -1, child: Text('전체')),
              ...List.generate(
                routeLabels.length,
                (index) => DropdownMenuItem(
                  value: index,
                  child: Text(routeLabels[index]),
                ),
              ),
            ],
"@
$s = $s.Replace($oldItems,$newItems)

$s = $s.Replace(
"          ..._results.map((r) => _shipmentCard(r)),",
"          ..._groupedResultWidgets(),"
)

$insertMarker = "  Widget _shipmentCard(Map<String, dynamic> r) {"
$helpers = @'
  String _groupKey(Map<String, dynamic> r) =>
      '${r['route'] ?? ''}|${r['shipment_year'] ?? ''}|${r['voyage'] ?? ''}';

  List<MapEntry<String, List<Map<String, dynamic>>>> _resultGroups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final row in _results) {
      map.putIfAbsent(_groupKey(row), () => <Map<String, dynamic>>[]).add(row);
    }
    return map.entries.toList();
  }

  void _toggleGroup(List<Map<String, dynamic>> rows) {
    final ids = rows.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  bool _isOwnShipment(Map<String, dynamic> r) {
    final user = widget.currentUser;
    if (user == null) return false;
    if ('${r['customer_id'] ?? ''}' == user.id) return true;
    final n1 = '${r['consignee_name'] ?? ''}'.trim().toLowerCase();
    final n2 = user.name.trim().toLowerCase();
    if (n1.isNotEmpty && n2.isNotEmpty && n1 == n2) return true;
    String digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');
    final p1 = digits('${r['consignee_phone'] ?? ''}');
    final p2 = digits(user.phone);
    return p1.length >= 8 && p2.length >= 8 &&
        p1.substring(p1.length - 8) == p2.substring(p2.length - 8);
  }

  Future<void> _showGroupFreight(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    try {
      final result = await FreightService.instance.calculate(rows);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  '${rows.first['route']} · ${rows.first['shipment_year']}년 · ${_voyageLabel(rows.first['voyage'])}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text('그룹 전체 운임'),
                const Divider(),
                ...result.lines.map((line) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('박스번호 ${line.boxNumber} · 송장번호 ${line.invoiceNumber}'),
                      subtitle: Text(
                        '청구중량 ${line.chargeableWeight.toStringAsFixed(2)}kg · 단가 \$${line.rate.toStringAsFixed(2)}/kg',
                      ),
                      trailing: Text('\$${line.amountUsd.toStringAsFixed(2)}'),
                    )),
                const Divider(),
                Text('USD  \$${result.totalUsd.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('KIP  ${result.totalKip.toStringAsFixed(0)}'),
                Text('THB  ${result.totalThb.toStringAsFixed(1)}'),
                Text('KRW  ${result.totalKrw.toStringAsFixed(0)}'),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('그룹 운임 계산 실패: $error')));
      }
    }
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
            ...rows.map(_shipmentCard),
          ],
        ),
      );
    }).toList();
  }

'@
if (-not $s.Contains($helpers.Trim())) {
  $s = $s.Replace($insertMarker, $helpers + $insertMarker)
}

# 그룹 내부 카드이므로 중복 Card 외곽을 제거하고 본인 화물만 녹색 테두리 표시
$s = $s.Replace(
"    return Card(`r`n      child: InkWell(",
"    return Container(`r`n      decoration: BoxDecoration(`r`n        border: _isOwnShipment(r) ? Border.all(color: Colors.green, width: 2) : null,`r`n        borderRadius: BorderRadius.circular(10),`r`n      ),`r`n      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),`r`n      child: InkWell("
)
# Container 변환 후 남는 Card 전용 닫힘 1개 제거
$s = $s.Replace("      ),`r`n    );`r`n  }`r`n`r`n  String _voyageLabel", "    );`r`n  }`r`n`r`n  String _voyageLabel")

Write-Utf8 $searchPath $s

# ------------------------------------------------------------------
# 2) 화물 관리: 전체 경로 + 그룹 UI + 팝업 편집/삭제/명세서
# ------------------------------------------------------------------
$cargoPath = Join-Path $project 'lib/screens/cargo_management_screen.dart'
$c = Read-Utf8 $cargoPath

if (-not $c.Contains("import '../services/freight_service.dart';")) {
  $c = $c.Replace(
    "import '../services/shipment_service.dart';",
    "import '../services/shipment_service.dart';`r`nimport '../services/freight_service.dart';"
  )
}
$c = $c.Replace("  String _route = routeLabels.first;", "  String _route = '전체';")

$c = $c.Replace(
"    final years =`r`n        ShipmentFilterOptionsService.instance.yearsFor(_filterBatches, _route);",
"    final years = _route == '전체'`r`n        ? (_filterBatches.map((e) => e.year).toSet().toList()..sort((a,b) => b.compareTo(a)))`r`n        : ShipmentFilterOptionsService.instance.yearsFor(_filterBatches, _route);"
)
$c = $c.Replace(
"    final voyages = ShipmentFilterOptionsService.instance`r`n        .voyagesFor(_filterBatches, _route, year);",
"    final voyages = _route == '전체'`r`n        ? (_filterBatches.where((e) => e.year == year).map((e) => e.voyage).toSet().toList())`r`n        : ShipmentFilterOptionsService.instance.voyagesFor(_filterBatches, _route, year);"
)

$c = $c.Replace(
"              items: routeLabels`r`n                  .map((route) => DropdownMenuItem(value: route, child: Text(route)))`r`n                  .toList(),",
"              items: <String>['전체', ...routeLabels]`r`n                  .map((route) => DropdownMenuItem(value: route, child: Text(route)))`r`n                  .toList(),"
)
$c = $c.Replace(
"              ..._results.map(_shipmentCard),",
"              ..._managementGroupWidgets(),"
)

# 기존 하단 즉시 편집 UI는 숨기고 그룹 편집 팝업으로 대체
$c = $c.Replace(
"            if (_selectedIds.isNotEmpty) ...[",
"            if (false && _selectedIds.isNotEmpty) ...["
)

$marker = "  Widget _shipmentCard(Map<String, dynamic> item) {"
$groupHelpers = @'
  String _managementGroupKey(Map<String, dynamic> r) =>
      '${r['route'] ?? ''}|${r['shipment_year'] ?? ''}|${r['voyage'] ?? ''}';

  List<MapEntry<String, List<Map<String, dynamic>>>> _managementGroups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final row in _results) {
      map.putIfAbsent(_managementGroupKey(row), () => <Map<String, dynamic>>[]).add(row);
    }
    return map.entries.toList();
  }

  void _toggleManagementGroup(List<Map<String, dynamic>> rows) {
    final ids = rows.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  List<Map<String, dynamic>> _checkedRowsInGroup(List<Map<String, dynamic>> rows) =>
      rows.where((r) => _selectedIds.contains('${r['id']}')).toList();

  Future<void> _editCheckedGroup(List<Map<String, dynamic>> rows) async {
    final selected = _checkedRowsInGroup(rows);
    if (selected.isEmpty) {
      _message('편집할 화물을 먼저 체크해 주세요.');
      return;
    }
    final one = selected.length == 1 ? selected.first : null;
    final name = TextEditingController(text: one == null ? '' : '${one['consignee_name'] ?? ''}');
    final phone = TextEditingController(text: one == null ? '' : '${one['consignee_phone'] ?? ''}');
    final notes = TextEditingController(text: one == null ? '' : '${one['notes'] ?? ''}');
    final weight = TextEditingController(text: one == null ? '' : '${one['weight_kg'] ?? ''}');
    final length = TextEditingController(text: one == null ? '' : '${one['length_cm'] ?? ''}');
    final width = TextEditingController(text: one == null ? '' : '${one['width_cm'] ?? ''}');
    final height = TextEditingController(text: one == null ? '' : '${one['height_cm'] ?? ''}');

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('화물 편집 (${selected.length}건)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected.length > 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '여러 화물 편집 시 입력한 항목만 선택 화물 전체에 적용됩니다.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              TextField(controller: name, decoration: const InputDecoration(labelText: '이름/수령인')),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '연락처')),
              TextField(controller: notes, decoration: const InputDecoration(labelText: '기타 내용')),
              if (_isManager) ...[
                TextField(controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '무게(kg)')),
                TextField(controller: length, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '가로(cm)')),
                TextField(controller: width, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '세로(cm)')),
                TextField(controller: height, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '높이(cm)')),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('화물 정보 저장')),
        ],
      ),
    );

    if (save == true) {
      final changes = <String, dynamic>{};
      if (name.text.trim().isNotEmpty) changes['consignee_name'] = name.text.trim();
      if (phone.text.trim().isNotEmpty) changes['consignee_phone'] = phone.text.trim();
      if (notes.text.trim().isNotEmpty) changes['notes'] = notes.text.trim();
      num? n(String v) => num.tryParse(v.trim());
      if (_isManager && n(weight.text) != null) changes['weight_kg'] = n(weight.text);
      if (_isManager && n(length.text) != null) changes['length_cm'] = n(length.text);
      if (_isManager && n(width.text) != null) changes['width_cm'] = n(width.text);
      if (_isManager && n(height.text) != null) changes['height_cm'] = n(height.text);

      if (changes.isEmpty) {
        _message('수정할 내용을 입력해 주세요.');
      } else {
        setState(() => _busy = true);
        try {
          for (final row in selected) {
            await ShipmentService.instance.updateRow('${row['id']}', changes);
          }
          _message('선택한 화물 정보를 저장했습니다.');
          await _search();
        } catch (error) {
          _message('화물 편집 실패: $error');
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
    }

    name.dispose(); phone.dispose(); notes.dispose();
    weight.dispose(); length.dispose(); width.dispose(); height.dispose();
  }

  Future<void> _deleteCheckedGroup(List<Map<String, dynamic>> rows) async {
    final selected = _checkedRowsInGroup(rows);
    if (selected.isEmpty) {
      _message('삭제할 화물을 먼저 체크해 주세요.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('선택 화물 삭제 대기'),
        content: Text('${selected.length}건을 삭제 대기로 이동하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('삭제 대기')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      for (final row in selected) {
        await ShipmentService.instance.requestShipmentDeletion('${row['id']}');
        _selectedIds.remove('${row['id']}');
      }
      await _loadPendingDeletions();
      await _search();
      _message('${selected.length}건을 삭제 대기로 이동했습니다.');
    } catch (error) {
      _message('그룹 삭제 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showGroupStatement(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty || _isPartner) return;
    try {
      final freight = await FreightService.instance.calculate(rows);
      if (!mounted) return;
      final receipts = rows
          .map((r) => '${r['receipt_number'] ?? ''}'.trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '${rows.first['route']} · ${rows.first['shipment_year']}년 · ${_voyageLabel(rows.first['voyage'])}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('그룹 전체 운임', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('박스 ${rows.length}건'),
                Text('USD  \$${freight.totalUsd.toStringAsFixed(2)}'),
                Text('KIP  ${freight.totalKip.toStringAsFixed(0)}'),
                Text('THB  ${freight.totalThb.toStringAsFixed(1)}'),
                Text('KRW  ${freight.totalKrw.toStringAsFixed(0)}'),
                const Divider(),
                if (receipts.isEmpty)
                  const Text('명세서를 열 수 있는 영수번호가 없습니다.')
                else ...[
                  const Text('영수번호별 명세서', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  ...receipts.map((receipt) => OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await showDialog<void>(
                        context: context,
                        builder: (_) => StatementPreviewDialog(
                          routeLabel: '${rows.first['route']}',
                          year: (rows.first['shipment_year'] as num).toInt(),
                          voyage: '${rows.first['voyage']}',
                          receiptNumber: receipt,
                        ),
                      );
                    },
                    child: Text('$receipt 명세서 보기'),
                  )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('닫기')),
          ],
        ),
      );
    } catch (error) {
      _message('그룹 명세서/운임 로딩 실패: $error');
    }
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
                      tooltip: '편집',
                      onPressed: _busy ? null : () => _editCheckedGroup(rows),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                  if (_isManager)
                    IconButton(
                      tooltip: '삭제',
                      onPressed: _busy ? null : () => _deleteCheckedGroup(rows),
                      icon: const Icon(Icons.delete_outline, size: 19),
                    ),
                  if (!_isPartner)
                    IconButton(
                      tooltip: '명세서 보기',
                      onPressed: _busy ? null : () => _showGroupStatement(rows),
                      icon: const Icon(Icons.receipt_long_outlined, size: 19),
                    ),
                ],
              ),
            ),
            ...rows.map(_groupShipmentCard),
          ],
        ),
      );
    }).toList();
  }

  Widget _groupShipmentCard(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final size =
        '${item['length_cm'] ?? ''} × ${item['width_cm'] ?? ''} × ${item['height_cm'] ?? ''} cm';
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: _selectedIds.contains(id)
            ? Border.all(color: AppColors.accent, width: 1.5)
            : null,
      ),
      child: InkWell(
        onTap: () => _toggle(id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _selectedIds.contains(id),
                onChanged: (_) => _toggle(id),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('박스번호 ${item['box_number'] ?? ''}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyPrimary)),
                    const SizedBox(height: 5),
                    _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
                    _infoRow('이름/수령인', '${item['consignee_name'] ?? ''}'),
                    _infoRow('연락처', '${item['consignee_phone'] ?? ''}'),
                    _infoRow('입고 날짜', '${item['received_at'] ?? ''}'),
                    _infoRow('무게', '${item['weight_kg'] ?? ''} kg'),
                    _infoRow('크기', size),
                    _infoRow('영수증 번호', '${item['receipt_number'] ?? ''}'),
                    if (_isAdmin || _isStaff)
                      _infoRow('구획 (Zone)', '${item['unloading_zone'] ?? ''}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

'@
if (-not $c.Contains($groupHelpers.Trim())) {
  $c = $c.Replace($marker, $groupHelpers + $marker)
}

Write-Utf8 $cargoPath $c

# ------------------------------------------------------------------
# 3) 명세서 미리보기: PNG 상단 빈 영역 crop 후 기존 좌표계를 실제 문서에 적용
# ------------------------------------------------------------------
$statementPath = Join-Path $project 'lib/screens/statement_preview_dialog.dart'
$t = Read-Utf8 $statementPath

$t = $t.Replace(
"  Size _logicalSize(ui.Image image) {`r`n    final rowHeight = image.height * .028;`r`n    final extra = (_detailRows - _baseRows) * rowHeight;`r`n    return Size(image.width.toDouble(), image.height + extra);`r`n  }",
"  double _cropRatio() =>`r`n      _formRouteKey == 'kr_la_sea' || _formRouteKey == 'kr_la_air' ? .402 : .468;`r`n`r`n  Size _logicalSize(ui.Image image) {`r`n    final visibleHeight = image.height * (1 - _cropRatio());`r`n    final rowHeight = visibleHeight * .028;`r`n    final extra = (_detailRows - _baseRows) * rowHeight;`r`n    return Size(image.width.toDouble(), visibleHeight + extra);`r`n  }"
)

$t = $t.Replace(
"        detailRows: _detailRows,`r`n      );",
"        detailRows: _detailRows,`r`n        sourceTop: image.height * _cropRatio(),`r`n      );"
)

$t = $t.Replace(
"    required this.detailRows,`r`n  });",
"    required this.detailRows,`r`n    required this.sourceTop,`r`n  });"
)
$t = $t.Replace(
"  final int detailRows;",
"  final int detailRows;`r`n  final double sourceTop;"
)

$oldPaint = @"
    final w = template.width.toDouble();
    final h = template.height.toDouble();
    final rowH = h * .028;
"@
$newPaint = @"
    final w = template.width.toDouble();
    final fullH = template.height.toDouble();
    final h = fullH - sourceTop;
    final rowH = h * .028;
"@
$t = $t.Replace($oldPaint,$newPaint)

$t = $t.Replace(
"      canvas.drawImage(template, Offset.zero, p);",
"      canvas.drawImageRect(`r`n        template,`r`n        Rect.fromLTWH(0, sourceTop, w, h),`r`n        Rect.fromLTWH(0, 0, w, h),`r`n        p,`r`n      );"
)

$t = $t.Replace(
"        Rect.fromLTWH(0, 0, w, bodyBottom),`r`n        Rect.fromLTWH(0, 0, w, bodyBottom),",
"        Rect.fromLTWH(0, sourceTop, w, bodyBottom),`r`n        Rect.fromLTWH(0, 0, w, bodyBottom),"
)
$t = $t.Replace(
"      final srcRow = Rect.fromLTWH(0, bodyBottom - rowH, w, rowH);",
"      final srcRow = Rect.fromLTWH(0, sourceTop + bodyBottom - rowH, w, rowH);"
)
$t = $t.Replace(
"        Rect.fromLTWH(0, bodyBottom, w, h - bodyBottom),",
"        Rect.fromLTWH(0, sourceTop + bodyBottom, w, h - bodyBottom),"
)

Write-Utf8 $statementPath $t

Write-Host ''
Write-Host 'Patch097 적용 완료' -ForegroundColor Green
Write-Host '- 화물 조회: 전체 경로 + 경로/년도/항차 그룹화 + 그룹 전체선택/운임'
Write-Host '- 화물 관리: 그룹화 + 그룹 편집/삭제/명세서 버튼 + 팝업 편집'
Write-Host '- 일반회원: 전체 본인 화물 이력 조회는 SQL062 적용 후 활성화'
Write-Host '- 명세서: statement PNG 상단 빈 영역 crop 정상화'
Write-Host ''
Write-Host '다음: SQL062 실행 -> flutter analyze -> flutter run'
