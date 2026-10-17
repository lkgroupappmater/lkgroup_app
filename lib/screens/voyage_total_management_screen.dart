import 'package:flutter/material.dart';

import '../core/money_format.dart';
import '../core/app_language.dart';
import '../services/supabase_service.dart';
import '../widgets/content_media.dart';
import '../services/excel_bulk_management_service.dart';
import '../services/receipt_settlement_service.dart';
import '../services/settlement_snapshot_service.dart';

class VoyageTotalManagementScreen extends StatefulWidget {
  const VoyageTotalManagementScreen({super.key, this.language = AppLanguage.korean});
  final AppLanguage language;

  @override
  State<VoyageTotalManagementScreen> createState() =>
      _VoyageTotalManagementScreenState();
}

class _VoyageTotalManagementScreenState
    extends State<VoyageTotalManagementScreen> {
  List<ExcelBulkBatch> _batches = const [];
  String? _route;
  int? _year;
  String? _voyage;
  VoyageSettlement? _settlement;
  bool _busy = true;
  List<Map<String, dynamic>> _summaries = const [];
  String? _loadError;
  String _text(String ko, String en, String lo) => sharedText(widget.language, ko, en, lo);

  List<ExcelBulkBatch> get _visibleBatches => _batches.where((b) =>
      (_route == null || b.route == _route) &&
      (_year == null || b.year == _year) &&
      (_voyage == null || b.voyage == _voyage)).toList();

  Widget _batchCard(ExcelBulkBatch batch) {
    Map<String, dynamic>? saved;
    for (final row in _summaries) {
      if ((row['route_key'] == batch.route || row['route_label'] == batch.route) &&
          row['shipment_year'] == batch.year && row['voyage'] == batch.voyage) {
        saved = row;
        break;
      }
    }
    String amount(String key) => MoneyFormat.usd((saved?[key] as num?)?.toDouble() ?? 0);
    return Card(child: ListTile(
      title: Text('${batch.route} · ${batch.year} · ${batch.voyage}'),
      subtitle: Text(saved == null
        ? _text('미계산', 'Not calculated', 'ຍັງບໍ່ຄິດໄລ່')
        : '${_text('할인 전', 'Gross', 'ຍອດລວມ')}: ${amount('gross_usd')} · '
          '${_text('할인', 'Discount', 'ສ່ວນຫຼຸດ')}: ${amount('discount_usd')}\n'
          '${_text('합계', 'Total', 'ລວມ')}: ${amount('net_usd')} · '
          '${_text('계산일', 'Calculated', 'ວັນຄິດໄລ່')}: ${saved['calculated_at']}'),
      isThreeLine: saved != null,
      trailing: const Icon(Icons.chevron_right),
      onTap: _busy ? null : () => setState(() {
        _route = batch.route; _year = batch.year; _voyage = batch.voyage;
        _settlement = null;
      }),
    ));
  }

  List<String> get _routes =>
      _batches.map((e) => e.route).toSet().toList()..sort();

  List<int> get _years => _batches
      .where((e) => _route == null || e.route == _route)
      .map((e) => e.year)
      .toSet()
      .toList()
    ..sort((a, b) => b.compareTo(a));

  List<String> get _voyages => _batches
      .where((e) =>
          (_route == null || e.route == _route) &&
          (_year == null || e.year == _year))
      .map((e) => e.voyage)
      .toSet()
      .toList()
    ..sort();

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    final owner = SupabaseService.isReady ? SupabaseService.client.auth.currentUser?.id : null;
    setState(() { _busy = true; _loadError = null; });
    try {
      final result = await Future.wait<Object>([
        ExcelBulkManagementService.instance.listBatches(),
        SettlementSnapshotService.instance.listSummaries(),
      ]);
      if (!mounted || (SupabaseService.isReady && owner != SupabaseService.client.auth.currentUser?.id)) return;
      setState(() {
        _batches = result[0] as List<ExcelBulkBatch>;
        _summaries = result[1] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _calculate() async {
    if (_route == null || _year == null || _voyage == null) {
      _msg('운송 경로, 년도, 항차를 모두 선택해 주세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      final rows = await ExcelBulkManagementService.instance.listRows(
        route: _route!,
        year: _year!,
        voyage: _voyage!,
      );
      final result =
          await ReceiptSettlementService.instance.calculate(rows);
      await SettlementSnapshotService.instance.save(
        routeKey: _route!,
        routeLabel: _route!,
        year: _year!,
        voyage: _voyage!,
        settlement: result,
      );
      if (!mounted) return;
      setState(() => _settlement = result);
      await _loadBatches();
    } catch (e) {
      _msg('항차별 총액 계산 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Widget _moneyCard(
    String label,
    double value, {
    bool emphasize = false,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight:
                        emphasize ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Text(
                MoneyFormat.usd(value),
                style: TextStyle(
                  fontSize: emphasize ? 22 : 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _settlement;
    return Scaffold(
      appBar: AppBar(title: const Text('항차별 총액 관리'), actions: [
        IconButton(onPressed: _busy ? null : _loadBatches, icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('route:$_route'),
            initialValue: _route,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '운송 경로',
              border: OutlineInputBorder(),
            ),
            items: _routes
                .map((e) =>
                    DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() {
              _route = v;
              _year = null;
              _voyage = null;
              _settlement = null;
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('year:$_route:$_year'),
                  initialValue: _year,
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
                  onChanged: _route == null
                      ? null
                      : (v) => setState(() {
                            _year = v;
                            _voyage = null;
                            _settlement = null;
                          }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('voyage:$_route:$_year:$_voyage'),
                  initialValue: _voyage,
                  decoration: const InputDecoration(
                    labelText: '항차',
                    border: OutlineInputBorder(),
                  ),
                  items: _voyages
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e.endsWith('항차') ? e : '${e}항차',
                            ),
                          ))
                      .toList(),
                  onChanged: _year == null
                      ? null
                      : (v) => setState(() {
                            _voyage = v;
                            _settlement = null;
                          }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _calculate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('실제 데이타 기준 총액 계산'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_loadError != null) Card(child: ListTile(
            title: Text(_loadError!),
            trailing: IconButton(onPressed: _loadBatches, icon: const Icon(Icons.refresh)),
          )),
          if (!_busy) ...[
            Row(children: [
              Expanded(child: Text(_text('항차별 합계', 'Voyage totals', 'ຍອດລວມຕາມຖ້ຽວ'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              TextButton(onPressed: () => setState(() {
                _route = null; _year = null; _voyage = null; _settlement = null;
              }), child: Text(_text('전체', 'All', 'ທັງໝົດ'))),
            ]),
            Text(_text('저장된 정산 기준입니다. 최신 금액은 총액 계산으로 갱신하세요.',
              'Saved settlement totals. Use Calculate to update the amounts.',
              'ຍອດລວມທີ່ບັນທຶກ. ກົດຄິດໄລ່ເພື່ອອັບເດດ.')),
            if (_visibleBatches.isEmpty && _loadError == null)
              Text(_text('등록된 항차가 없습니다.', 'No voyages found.', 'ບໍ່ພົບຖ້ຽວ.')),
            ..._visibleBatches.map(_batchCard),
          ],
          if (!_busy && s != null) ...[
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                title: const Text('실제 총 물품 개수'),
                trailing: Text(
                  '${s.totalQuantity}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _moneyCard('할인 전 총액', s.grossUsd),
            _moneyCard('총 할인 금액', s.discountUsd),
            _moneyCard(
              '실제 총액 (총액 - 할인)',
              s.netUsd,
              emphasize: true,
            ),
            if (s.discountByGroup.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '단체별 할인 금액',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              ...s.discountByGroup.entries.map(
                (e) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.percent),
                  title: Text(e.key),
                  trailing: Text(
                    MoneyFormat.usd(e.value),
                    style:
                        const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              '영수번호별 정산 (${s.receipts.length}건)',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            ...s.receipts.map(
              (r) => Card(
                child: ExpansionTile(
                  title: Text(
                    '${r.receiptNumber} · '
                    '${r.customerName.isEmpty ? '수취인 미확인' : r.customerName}',
                  ),
                  subtitle: Text(
                    '${r.totalQuantity}개 · '
                    '실제 ${MoneyFormat.usd(r.netUsd)}',
                  ),
                  children: [
                    ListTile(
                      dense: true,
                      title: const Text('할인 전'),
                      trailing: Text(MoneyFormat.usd(r.grossUsd)),
                    ),
                    ListTile(
                      dense: true,
                      title: const Text('할인'),
                      trailing: Text(
                        '-${MoneyFormat.usd(r.discountUsd)}',
                      ),
                    ),
                    ListTile(
                      dense: true,
                      title: const Text(
                        '최종 실제 금액',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: Text(
                        MoneyFormat.usd(r.netUsd),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

