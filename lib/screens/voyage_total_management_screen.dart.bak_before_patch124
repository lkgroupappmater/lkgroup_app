import 'package:flutter/material.dart';

import '../core/money_format.dart';
import '../services/excel_bulk_management_service.dart';
import '../services/freight_service.dart';

class VoyageTotalManagementScreen extends StatefulWidget {
  const VoyageTotalManagementScreen({super.key});

  @override
  State<VoyageTotalManagementScreen> createState() => _VoyageTotalManagementScreenState();
}

class _VoyageTotalManagementScreenState extends State<VoyageTotalManagementScreen> {
  List<ExcelBulkBatch> _batches = const [];
  String? _route;
  int? _year;
  String? _voyage;
  FreightCalculation? _freight;
  int _totalQty = 0;
  bool _busy = true;

  List<String> get _routes => _batches.map((e) => e.route).toSet().toList()..sort();
  List<int> get _years => _batches.where((e) => _route == null || e.route == _route).map((e) => e.year).toSet().toList()..sort((a,b)=>b.compareTo(a));
  List<String> get _voyages => _batches.where((e) => (_route == null || e.route == _route) && (_year == null || e.year == _year)).map((e) => e.voyage).toSet().toList()..sort();

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final rows = await ExcelBulkManagementService.instance.listBatches();
      if (mounted) setState(() => _batches = rows);
    } catch (e) {
      if (mounted) _msg('항차 목록 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _qty(dynamic v) {
    final n = num.tryParse('${v ?? ''}'.replaceAll(',', '').trim());
    return (n ?? 1).round().clamp(1, 999999).toInt();
  }

  Future<void> _calculate() async {
    if (_route == null || _year == null || _voyage == null) {
      _msg('운송 경로, 년도, 항차를 모두 선택해 주세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      final rows = await ExcelBulkManagementService.instance.listRows(route: _route!, year: _year!, voyage: _voyage!);
      final result = await FreightService.instance.calculate(rows);
      if (!mounted) return;
      setState(() {
        _freight = result;
        _totalQty = rows.fold<int>(0, (sum, row) => sum + _qty(row['quantity']));
      });
    } catch (e) {
      _msg('항차별 총액 계산 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _moneyCard(String label, double value, {bool emphasize = false}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600))),
            Text(MoneyFormat.usd(value), style: TextStyle(fontSize: emphasize ? 22 : 18, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = _freight;
    return Scaffold(
      appBar: AppBar(title: const Text('항차별 총액 관리')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _route,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '운송 경로', border: OutlineInputBorder()),
            items: _routes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() { _route=v; _year=null; _voyage=null; _freight=null; }),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: '년도', border: OutlineInputBorder()),
              items: _years.map((e) => DropdownMenuItem(value: e, child: Text('$e년'))).toList(),
              onChanged: _route == null ? null : (v) => setState(() { _year=v; _voyage=null; _freight=null; }),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _voyage,
              decoration: const InputDecoration(labelText: '항차', border: OutlineInputBorder()),
              items: _voyages.map((e) => DropdownMenuItem(value: e, child: Text(e.endsWith('항차') ? e : '${e}항차'))).toList(),
              onChanged: _year == null ? null : (v) => setState(() { _voyage=v; _freight=null; }),
            )),
          ]),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : _calculate, icon: const Icon(Icons.calculate_outlined), label: const Text('실제 데이타 기준 총액 계산')),
          if (_busy) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
          if (!_busy && f != null) ...[
            const SizedBox(height: 14),
            Card(child: ListTile(title: const Text('실제 총 물품 개수'), trailing: Text('$_totalQty', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)))),
            _moneyCard('할인 전 총액', f.grossTotalUsd),
            _moneyCard('총 할인 금액', f.discountTotalUsd),
            _moneyCard('실제 총액 (총액 - 할인)', f.totalUsd, emphasize: true),
            if (f.discountByGroup.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('단체별 할인 금액', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ...f.discountByGroup.entries.map((e) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.percent),
                    title: Text(e.key),
                    trailing: Text(MoneyFormat.usd(e.value), style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
            ],
            const SizedBox(height: 12),
            const Text('할인 적용 고객', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ...f.lines.where((e) => e.discountAmountUsd > 0).map((e) => ListTile(
              dense: true,
              title: Text('${e.discountCustomer.isEmpty ? e.boxNumber : e.discountCustomer} · ${e.discountGroup.isEmpty ? '기타 할인' : e.discountGroup}'),
              subtitle: Text('${(e.discountPercent * 100).toStringAsFixed(1)}% · ${e.boxNumber}'),
              trailing: Text('-${MoneyFormat.usd(e.discountAmountUsd)}'),
            )),
          ],
        ],
      ),
    );
  }
}
