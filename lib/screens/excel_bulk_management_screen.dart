import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../services/excel_bulk_management_service.dart';
import '../services/shipment_service.dart';

class ExcelBulkManagementScreen extends StatefulWidget {
  const ExcelBulkManagementScreen({super.key});

  @override
  State<ExcelBulkManagementScreen> createState() =>
      _ExcelBulkManagementScreenState();
}

class _ExcelBulkManagementScreenState extends State<ExcelBulkManagementScreen> {
  List<ExcelBulkBatch> _batches = const [];
  List<Map<String, dynamic>> _rows = const [];
  final Set<String> _checked = <String>{};

  String? _route;
  int? _year;
  String? _voyage;
  bool _busy = true;
  bool _lockedOnly = false;

  List<Map<String, dynamic>> get _visibleRows => _lockedOnly
      ? _rows.where((e) => e['data_locked'] == true).toList(growable: false)
      : _rows;

  int get _lockedCount =>
      _rows.where((e) => e['data_locked'] == true).length;

  List<String> get _routes =>
      _batches.map((e) => e.route).where((e) => e.isNotEmpty).toSet().toList()
        ..sort();

  List<int> get _years {
    final values = _batches
        .where((e) => _route == null || e.route == _route)
        .map((e) => e.year)
        .where((e) => e > 0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }

  List<String> get _voyages {
    final values = _batches
        .where((e) =>
            (_route == null || e.route == _route) &&
            (_year == null || e.year == _year))
        .map((e) => e.voyage)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    return values;
  }

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    setState(() => _busy = true);
    try {
      final batches = await ExcelBulkManagementService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        if (_route != null && !_routes.contains(_route)) _route = null;
        if (_year != null && !_years.contains(_year)) _year = null;
        if (_voyage != null && !_voyages.contains(_voyage)) _voyage = null;
      });
    } catch (error) {
      _message('항차 목록 조회 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadRows() async {
    if (_route == null || _year == null || _voyage == null) {
      setState(() {
        _rows = const [];
        _checked.clear();
      });
      return;
    }

    setState(() => _busy = true);
    try {
      final rows = await ExcelBulkManagementService.instance.listRows(
        route: _route!,
        year: _year!,
        voyage: _voyage!,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _checked.clear();
        if (_lockedOnly && !rows.any((e) => e['data_locked'] == true)) {
          _lockedOnly = false;
        }
        if (_lockedOnly) {
          _checked.addAll(
            rows
                .where((e) => e['data_locked'] == true)
                .map((e) => '${e['id']}'),
          );
        }
      });
    } catch (error) {
      _message('화물 데이터 조회 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _routeChanged(String? value) {
    setState(() {
      _route = value;
      _year = null;
      _voyage = null;
      _rows = const [];
      _checked.clear();
    });
  }

  void _yearChanged(int? value) {
    setState(() {
      _year = value;
      _voyage = null;
      _rows = const [];
      _checked.clear();
    });
  }

  void _voyageChanged(String? value) {
    setState(() {
      _voyage = value;
      _rows = const [];
      _checked.clear();
    });
    if (value != null) _loadRows();
  }

  void _toggle(String id) {
    setState(() {
      if (!_checked.remove(id)) _checked.add(id);
    });
  }

  void _toggleAll(bool checked) {
    final visible = _visibleRows;
    setState(() {
      if (checked) {
        _checked
          ..clear()
          ..addAll(visible.map((e) => '${e['id']}'));
      } else {
        _checked.clear();
      }
    });
  }

  void _toggleLockedOnly() {
    if (_lockedOnly) {
      setState(() {
        _lockedOnly = false;
        _checked.clear();
      });
      return;
    }

    final locked = _rows.where((e) => e['data_locked'] == true).toList();
    if (locked.isEmpty) {
      _message('현재 잠금된 화물이 없습니다.');
      return;
    }
    setState(() {
      _lockedOnly = true;
      _checked
        ..clear()
        ..addAll(locked.map((e) => '${e['id']}'));
    });
  }

  Future<void> _unlockSingle(Map<String, dynamic> row) async {
    if (_busy || row['data_locked'] != true) return;
    final id = '${row['id']}';
    setState(() => _busy = true);
    try {
      await ExcelBulkManagementService.instance.setLocked([id], false);
      if (!mounted) return;
      setState(() {
        row['data_locked'] = false;
        _checked.remove(id);
        if (_lockedOnly &&
            !_rows.any((e) => e['data_locked'] == true)) {
          _lockedOnly = false;
        }
      });
      _message('해당 화물 잠금을 해제했습니다.');
    } catch (error) {
      _message('잠금 해제 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleReceiptRows(List<Map<String, dynamic>> rows) {
    final ids = rows.map((e) => '${e['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _checked.containsAll(ids)) {
        _checked.removeAll(ids);
      } else {
        _checked.addAll(ids);
      }
    });
  }

  Future<void> _setLock(bool locked) async {
    if (_checked.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ExcelBulkManagementService.instance
          .setLocked(_checked.toList(), locked);
      _message(locked ? '선택한 화물 데이터를 잠금했습니다.' : '선택한 화물 데이터 잠금을 해제했습니다.');
      await _loadRows();
    } catch (error) {
      _message('잠금 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeleteSelected() async {
    if (_checked.isEmpty) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('화물 삭제'),
            content: Text(
              '선택한 ${_checked.length}개의 화물을 삭제 합니다.\n\n'
              '30일 뒤에 자동으로 완전히 삭제 되며, 필요시 삭제 취소 혹은 바로 삭제가 가능 합니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _busy = true);
    try {
      for (final id in _checked.toList()) {
        await ShipmentService.instance.requestShipmentDeletion(id);
      }
      _message('선택한 화물을 삭제 처리했습니다. 30일 동안 복구할 수 있습니다.');
      await _loadRows();
      await _loadBatches();
    } catch (error) {
      _message('화물 삭제 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final box = TextEditingController(text: '${row['box_number'] ?? ''}');
    final invoice =
        TextEditingController(text: '${row['invoice_number'] ?? ''}');
    final special = TextEditingController(text: '${row['sender_name'] ?? ''}');
    final name = TextEditingController(text: '${row['consignee_name'] ?? ''}');
    final phone = TextEditingController(text: '${row['consignee_phone'] ?? ''}');
    final receipt =
        TextEditingController(text: '${row['receipt_number'] ?? ''}');
    final zone =
        TextEditingController(text: '${row['unloading_zone'] ?? ''}');
    final notes = TextEditingController(text: '${row['notes'] ?? ''}');

    final save = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('화물 데이터 편집 · ${row['box_number'] ?? ''}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(box, '화물번호'),
                  _field(invoice, '송장번호'),
                  _field(special, '특이사항', maxLines: 2),
                  if ('${row['special_note_auto'] ?? ''}'.trim().isNotEmpty)
                    _readOnly('${row['special_note_auto'] ?? ''}', '자동 매칭 특이사항'),
                  _field(name, '이름'),
                  _field(phone, '전화번호'),
                  _field(receipt, '영수번호'),
                  _field(zone, '구획'),
                  _field(notes, '비고', maxLines: 3),
                  if (row['data_locked'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.lock, size: 16, color: Colors.redAccent),
                          SizedBox(width: 5),
                          Text(
                            '데이터 수정 잠금된 화물',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('저장'),
              ),
            ],
          ),
        ) ??
        false;

    if (save) {
      try {
        await ExcelBulkManagementService.instance.updateRow(
          id: '${row['id']}',
          boxNumber: box.text,
          invoiceNumber: invoice.text,
          senderName: special.text,
          name: name.text,
          phone: phone.text,
          receiptNumber: receipt.text,
          unloadingZone: zone.text,
          notes: notes.text,
        );
        _message('화물 데이터를 수정했습니다.');
        await _loadRows();
      } catch (error) {
        _message('수정 실패: $error');
      }
    }

    // Dialog reverse transition 종료 전에 controller를 dispose하지 않습니다.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    box.dispose();
    invoice.dispose();
    special.dispose();
    name.dispose();
    phone.dispose();
    receipt.dispose();
    zone.dispose();
    notes.dispose();
  }

  Widget _field(TextEditingController controller, String label,
          {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _readOnly(String value, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          initialValue: value,
          readOnly: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            filled: true,
            isDense: true,
          ),
        ),
      );

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _visibleRows;
    final visibleIds = visibleRows.map((e) => '${e['id']}').toSet();
    final allChecked = visibleIds.isNotEmpty && _checked.containsAll(visibleIds);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in visibleRows) {
      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      grouped.putIfAbsent(
        receipt.isEmpty ? '(영수번호 없음)' : receipt,
        () => <Map<String, dynamic>>[],
      ).add(row);
    }

    int receiptTail(String value) {
      final match = RegExp(r'(\d+)\s*$').firstMatch(value);
      return match == null ? 999999 : int.tryParse(match.group(1)!) ?? 999999;
    }

    final groups = grouped.entries.toList()
      ..sort((a, b) {
        final n = receiptTail(a.key).compareTo(receiptTail(b.key));
        return n != 0 ? n : a.key.compareTo(b.key);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('엑셀 데이타 일괄 관리'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _route,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '운송 경로',
                    border: OutlineInputBorder(),
                  ),
                  items: _routes
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: _routeChanged,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _year,
                        decoration: const InputDecoration(
                          labelText: '년도',
                          border: OutlineInputBorder(),
                        ),
                        items: _years
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('$e년'),
                                ))
                            .toList(),
                        onChanged: _route == null ? null : _yearChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _voyage,
                        decoration: const InputDecoration(
                          labelText: '항차',
                          border: OutlineInputBorder(),
                        ),
                        items: _voyages
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('${e}항차'),
                                ))
                            .toList(),
                        onChanged: _route == null || _year == null
                            ? null
                            : _voyageChanged,
                      ),
                    ),
                  ],
                ),
                if (_rows.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _lockedOnly
                          ? '잠금만 보기 · ${_lockedCount}개'
                          : '선택 ${_checked.length}개',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _busy && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _voyage == null
                    ? const Center(
                        child: Text('운송 경로, 년도, 항차를 선택해 주세요.'),
                      )
                    : _rows.isEmpty
                        ? const Center(
                            child: Text('해당 항차 화물 데이터가 없습니다.'),
                          )
                        : visibleRows.isEmpty
                            ? const Center(
                                child: Text('현재 조건에 해당하는 화물이 없습니다.'),
                              )
                            : ListView(
                            padding:
                                const EdgeInsets.fromLTRB(10, 8, 10, 88),
                            children: groups.expand((entry) {
                              final groupRows = entry.value;
                              final groupIds =
                                  groupRows.map((e) => '${e['id']}').toSet();
                              final groupChecked = groupIds.isNotEmpty &&
                                  _checked.containsAll(groupIds);
                              final first = groupRows.first;
                              final zone =
                                  '${first['unloading_zone'] ?? ''}'.trim();

                              return <Widget>[
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    5,
                                    4,
                                    5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              const TextSpan(
                                                text: '영수번호: ',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              TextSpan(
                                                text: entry.key,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const TextSpan(
                                                text: ' / 구획: ',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              TextSpan(
                                                text:
                                                    zone.isEmpty ? '-' : zone,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const TextSpan(
                                                text: ' · 총 ',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              TextSpan(
                                                text: '${groupRows.length}개',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Checkbox(
                                        value: groupChecked,
                                        onChanged: (_) =>
                                            _toggleReceiptRows(groupRows),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                                ...groupRows.map(_rowCard),
                                const SizedBox(height: 8),
                              ];
                            }).toList(),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: _rows.isEmpty
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Material(
                elevation: 14,
                borderRadius: BorderRadius.circular(22),
                color: Colors.transparent,
                shadowColor: Colors.black38,
                child: Container(
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppColors.navyPrimary,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .12),
                    ),
                  ),
                  child: Row(
                    children: [
                      _bulkBarAction(
                        icon: allChecked
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        label: '전체',
                        enabled: _rows.isNotEmpty && !_busy,
                        onTap: () => _toggleAll(!allChecked),
                      ),
                      _bulkBarDivider(),
                      _bulkBarAction(
                        icon: _lockedOnly ? Icons.lock : Icons.lock_outline,
                        label: _lockedOnly ? '잠금만' : '잠금',
                        enabled: _lockedCount > 0 || _checked.isNotEmpty,
                        forceRed: true,
                        onTap: () {
                          if (_lockedOnly || _checked.isEmpty) {
                            _toggleLockedOnly();
                          } else {
                            _setLock(true);
                          }
                        },
                      ),
                      _bulkBarDivider(),
                      _bulkBarAction(
                        icon: Icons.lock_open_outlined,
                        label: '해체',
                        enabled: _checked.isNotEmpty && !_busy,
                        onTap: () => _setLock(false),
                      ),
                      _bulkBarDivider(),
                      _bulkBarAction(
                        icon: Icons.delete_outline,
                        label: '삭제',
                        enabled: _checked.isNotEmpty && !_busy,
                        onTap: _requestDeleteSelected,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
  Widget _bulkBarDivider() => Container(
        width: 1,
        height: 32,
        color: Colors.white.withValues(alpha: .16),
      );

  Widget _bulkBarAction({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool forceRed = false,
  }) =>
      Expanded(
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(15),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: !enabled
                    ? Colors.white38
                    : forceRed
                        ? Colors.redAccent
                        : AppColors.tealAccent,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: enabled ? Colors.white : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _rowCard(Map<String, dynamic> row) {
    final id = '${row['id']}';
    final locked = row['data_locked'] == true;
    final name = '${row['consignee_name'] ?? ''}'.trim();
    final phone = '${row['consignee_phone'] ?? ''}'.trim();
    final notes = '${row['notes'] ?? ''}'.trim();

    return Card(
      margin: const EdgeInsets.only(top: 5),
      child: InkWell(
        onTap: () => _toggle(id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 4, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _checked.contains(id),
                onChanged: (_) => _toggle(id),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['box_number'] ?? ''} · ${row['invoice_number'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${name.isEmpty ? '-' : name} / ${phone.isEmpty ? '-' : phone}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '비고: $notes',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              if (locked)
                IconButton(
                  tooltip: '잠금 해제',
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : () => _unlockSingle(row),
                  icon: const Icon(
                    Icons.lock,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                ),
              IconButton(
                tooltip: '편집',
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : () => _edit(row),
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _line(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '$label: ${value ?? ''}',
          style: const TextStyle(fontSize: 12),
        ),
      );
}

