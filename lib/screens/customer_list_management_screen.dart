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
  List<Map<String, dynamic>> _batchRows = const [];
  List<Map<String, dynamic>> _rows = const [];

  List<String> get _routes => {
        for (final r in _batchRows) '${r['route'] ?? ''}'.trim(),
      }.where((e) => e.isNotEmpty).toList()
        ..sort();

  List<int> get _years => {
        for (final r in _batchRows)
          if ((r['shipment_year'] as num?)?.toInt() case final int y) y,
      }.toList()
        ..sort((a, b) => b.compareTo(a));

  List<String> get _voyages => {
        for (final r in _batchRows)
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
        _batchRows = all;
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
            'receipt_number,consignee_name,consignee_phone,unloading_zone,special_note_auto,box_number,locked',
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
        result.add({
          'receipt': entry.key,
          'name': '${first['consignee_name'] ?? ''}'.trim(),
          'phone': '${first['consignee_phone'] ?? ''}'.trim(),
          'zone': '${first['unloading_zone'] ?? ''}'.trim(),
          'note': notes,
          'count': entry.value.length,
          'locked': entry.value.every((e) => e['locked'] == true),
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
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(text(e))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes;
    final years = _years;
    final voyages = _voyages;
    return Scaffold(
      appBar: AppBar(title: const Text('고객 리스트')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                _selector<String>(
                  label: '운송 경로',
                  value: _route,
                  items: routes,
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
                  items: years,
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
                  items: voyages,
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
                              '${r['count']}건',
                              if (r['locked'] == true) '잠금/확정',
                              if (note.isNotEmpty) note,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
