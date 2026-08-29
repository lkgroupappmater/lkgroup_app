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
    setState(() {
      if (checked) {
        _checked
          ..clear()
          ..addAll(_rows.map((e) => '${e['id']}'));
      } else {
        _checked.clear();
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
            title: const Text('화물 삭제 대기'),
            content: Text(
              '선택한 ${_checked.length}개 화물을 기존 삭제 로직과 동일하게 삭제 대기로 이동하시겠습니까?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제 대기'),
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
      _message('선택한 화물을 삭제 대기로 이동했습니다.');
      await _loadRows();
      await _loadBatches();
    } catch (error) {
      _message('삭제 대기 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final box = TextEditingController(text: '${row['box_number'] ?? ''}');
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
                  _field(box, '박스번호'),
                  _readOnly('${row['invoice_number'] ?? ''}', '송장번호 (수정 불가)'),
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

    box.dispose();
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
    final allChecked =
        _rows.isNotEmpty && _checked.length == _rows.length;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      grouped.putIfAbsent(
        receipt.isEmpty ? '(영수번호 없음)' : receipt,
        () => <Map<String, dynamic>>[],
      ).add(row);
    }

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
                        onChanged:
                            _route == null || _year == null ? null : _voyageChanged,
                      ),
                    ),
                  ],
                ),
                if (_rows.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: allChecked,
                        onChanged: (v) => _toggleAll(v == true),
                      ),
                      const Text('전체 체크/해제'),
                      const Spacer(),
                      Text('선택 ${_checked.length}개'),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        onPressed: _checked.isEmpty || _busy
                            ? null
                            : () => _setLock(true),
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text('편집 잠금'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _checked.isEmpty || _busy
                            ? null
                            : () => _setLock(false),
                        icon: const Icon(Icons.lock_open_outlined, size: 18),
                        label: const Text('잠금 해제'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _checked.isEmpty || _busy
                            ? null
                            : _requestDeleteSelected,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('삭제 대기'),
                      ),
                    ],
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
                    ? const Center(child: Text('운송 경로, 년도, 항차를 선택해 주세요.'))
                    : _rows.isEmpty
                        ? const Center(child: Text('해당 항차 화물 데이터가 없습니다.'))
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 30),
                            children: grouped.entries.expand((entry) {
                              final cards = entry.value.map(_rowCard);
                              return <Widget>[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  color: AppColors.primary.withValues(alpha: .08),
                                  child: Text(
                                    '영수번호 ${entry.key} · ${entry.value.length}개',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                ...cards,
                                const SizedBox(height: 8),
                              ];
                            }).toList(),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _rowCard(Map<String, dynamic> row) {
    final id = '${row['id']}';
    final locked = row['data_locked'] == true;
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => _edit(row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _checked.contains(id),
                onChanged: (_) => _toggle(id),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${row['box_number'] ?? ''} · ${row['invoice_number'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        if (locked)
                          const Icon(
                            Icons.lock,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _line('이름', row['consignee_name']),
                    _line('전화번호', row['consignee_phone']),
                    _line('영수번호', row['receipt_number']),
                    _line('구획', row['unloading_zone']),
                    _line('비고', row['notes']),
                  ],
                ),
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
