import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

class CustomerListManagementScreen extends StatefulWidget {
  const CustomerListManagementScreen({super.key});

  @override
  State<CustomerListManagementScreen> createState() =>
      _CustomerListManagementScreenState();
}

class _CustomerListManagementScreenState
    extends State<CustomerListManagementScreen> {
  bool _loading = true;
  String? _route;
  int? _year;
  String? _voyage;
  List<Map<String, dynamic>> _batches = const [];
  List<Map<String, dynamic>> _rows = const [];

  List<String> get _routes => {
        for (final r in _batches) '${r['route'] ?? ''}'.trim(),
      }.where((e) => e.isNotEmpty).toList()
        ..sort();

  List<int> get _years => {
        for (final r in _batches)
          if ((r['shipment_year'] as num?)?.toInt() case final int y) y,
      }.toList()
        ..sort((a, b) => b.compareTo(a));

  List<String> get _voyages => {
        for (final r in _batches)
          if (_route == '${r['route'] ?? ''}'.trim() &&
              _year == (r['shipment_year'] as num?)?.toInt())
            '${r['voyage'] ?? ''}'.trim(),
      }.where((e) => e.isNotEmpty).toList()
        ..sort((a, b) {
          int n(String v) =>
              int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          return n(b).compareTo(n(a));
        });

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final raw = await SupabaseService.client
          .from('shipments')
          .select('route,shipment_year,voyage')
          .isFilter('deletion_requested_at', null)
          .order('shipment_year', ascending: false);
      final all = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _batches = all;
        _route = _routes.isNotEmpty ? _routes.first : null;
        _year = _years.isNotEmpty ? _years.first : null;
        _voyage = _voyages.isNotEmpty ? _voyages.first : null;
        _loading = false;
      });
      await _loadRows();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('고객 리스트 조회 실패: $e')));
    }
  }

  Future<void> _loadRows() async {
    if (_route == null || _year == null || _voyage == null) return;
    setState(() => _loading = true);
    try {
      final raw = await SupabaseService.client
          .from('shipments')
          .select(
            'id,receipt_number,consignee_name,consignee_phone,unloading_zone,special_note_auto,box_number,quantity',
          )
          .eq('route', _route!)
          .eq('shipment_year', _year!)
          .eq('voyage', _voyage!)
          .isFilter('deletion_requested_at', null)
          .order('receipt_number')
          .order('box_number');
      final source = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in source) {
        final receipt = '${row['receipt_number'] ?? ''}'.trim();
        if (receipt.isEmpty) continue;
        grouped.putIfAbsent(receipt, () => []).add(row);
      }

      final result = <Map<String, dynamic>>[];
      for (final entry in grouped.entries) {
        final first = entry.value.first;
        final notes = entry.value
            .map((e) => '${e['special_note_auto'] ?? ''}'.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .join(' / ');
        final quantity = entry.value.fold<num>(
          0,
          (sum, row) => sum + ((row['quantity'] as num?) ?? 0),
        );
        result.add({
          'receipt': entry.key,
          'name': '${first['consignee_name'] ?? ''}'.trim(),
          'phone': '${first['consignee_phone'] ?? ''}'.trim(),
          'zone': '${first['unloading_zone'] ?? ''}'.trim(),
          'note': notes,
          'count': entry.value.length,
          'quantity': quantity,
        });
      }

      if (!mounted) return;
      setState(() {
        _rows = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('고객 리스트 조회 실패: $e')));
    }
  }

  Future<void> _editReceiptZone(Map<String, dynamic> row) async {
    final oldReceipt = '${row['receipt'] ?? ''}'.trim();
    final receiptController = TextEditingController(text: oldReceipt);
    final zoneController = TextEditingController(text: '${row['zone'] ?? ''}'.trim());
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${row['name'] ?? ''} 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: receiptController,
              decoration: const InputDecoration(labelText: '영수증 번호'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: zoneController,
              decoration: const InputDecoration(labelText: '구획(Zone)'),
            ),
            const SizedBox(height: 8),
            const Text(
              '현재 영수증 번호에 묶인 화물 전체에 동일하게 적용됩니다.',
              style: TextStyle(fontSize: 12),
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
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (save != true) return;
    final newReceipt = receiptController.text.trim();
    final newZone = zoneController.text.trim().toUpperCase();
    if (newReceipt.isEmpty || newZone.isEmpty) return;
    try {
      await SupabaseService.client
          .from('shipments')
          .update({
            'receipt_number': newReceipt,
            'unloading_zone': newZone,
          })
          .eq('route', _route!)
          .eq('shipment_year', _year!)
          .eq('voyage', _voyage!)
          .eq('receipt_number', oldReceipt)
          .isFilter('deletion_requested_at', null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('영수증 번호 / Zone 수정 완료')),
        );
      }
      await _loadRows();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수정 실패: $e')),
        );
      }
    }
  }

  Widget _selector<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) text,
    required ValueChanged<T?> onChanged,
  }) {
    return Expanded(
      child: DropdownButtonFormField<T>(
        value: items.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(text(e), overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('고객 리스트')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                _selector<String>(
                  label: '운송 경로',
                  value: _route,
                  items: _routes,
                  text: (v) => v,
                  onChanged: (v) {
                    setState(() {
                      _route = v;
                      _year = _years.isNotEmpty ? _years.first : null;
                      _voyage = _voyages.isNotEmpty ? _voyages.first : null;
                    });
                    _loadRows();
                  },
                ),
                const SizedBox(width: 8),
                _selector<int>(
                  label: '년도',
                  value: _year,
                  items: _years,
                  text: (v) => '$v년',
                  onChanged: (v) {
                    setState(() {
                      _year = v;
                      _voyage = _voyages.isNotEmpty ? _voyages.first : null;
                    });
                    _loadRows();
                  },
                ),
                const SizedBox(width: 8),
                _selector<String>(
                  label: '항차',
                  value: _voyage,
                  items: _voyages,
                  text: (v) => v.endsWith('항차') ? v : '$v항차',
                  onChanged: (v) {
                    setState(() => _voyage = v);
                    _loadRows();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '고객 ${_rows.length}명',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '새로고침',
                  onPressed: _loading ? null : _loadRows,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final r = _rows[index];
                        final note = '${r['note'] ?? ''}';
                        return ListTile(
                          dense: true,
                          leading: SizedBox(
                            width: 62,
                            child: Text(
                              '${r['receipt']}',
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          title: Text(
                            '${r['name']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            [
                              if ('${r['phone']}'.isNotEmpty) '${r['phone']}',
                              'Zone ${r['zone']}',
                              '수량 ${r['quantity']}',
                              if (note.isNotEmpty) note,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: '영수증 번호 / Zone 수정',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _editReceiptZone(r),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '현재 항차 · 고객 ${_rows.length}명 · 총 수량 ${_rows.fold<num>(0, (sum, row) => sum + ((row['quantity'] as num?) ?? 0))}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
