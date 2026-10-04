import 'package:flutter/material.dart';
import '../services/excel_export_service.dart';
import '../services/supabase_service.dart';

class ExcelStatementControlsScreen extends StatefulWidget {
  const ExcelStatementControlsScreen({super.key, required this.batch});
  final ExcelExportBatch batch;
  @override
  State<ExcelStatementControlsScreen> createState() => _ExcelStatementControlsState();
}

class _ExcelStatementControlsState extends State<ExcelStatementControlsScreen> {
  Map<String, dynamic>? _data;
  String _query = '', _error = '';
  bool _busy = false;
  final Set<String> _selected = {};
  Map<String, dynamic> get _params => {'p_route': widget.batch.routeLabel, 'p_year': widget.batch.year, 'p_voyage': widget.batch.voyage};
  List<Map<String, dynamic>> rows(dynamic value) => (value as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  bool matches(Map<String, dynamic> row) => '${row['name']} ${row['phone']} ${row['receipt_number']} ${row['customer_codes']}'.toLowerCase().contains(_query.trim().toLowerCase());
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final result = await SupabaseService.client.rpc('admin_excel_statement_controls', params: _params);
      if (mounted) setState(() { _data = Map<String, dynamic>.from(result as Map); _error = ''; _selected.removeWhere((n) => !rows(_data!['receipts']).any((r) => r['receipt_number'] == n)); });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  Future<void> _act(String name, Map<String, dynamic> params) async {
    if (_busy) return;
    setState(() => _busy = true);
    try { await SupabaseService.client.rpc(name, params: params); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _manual(Map<String, dynamic> r) async {
    final controller = TextEditingController(text: '${r['receipt_number']}');
    final number = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('명세서 번호 수동 지정'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '명세서 번호')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('저장'))],
    ));
    // A dialog may retain its text field during its closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (number != null && mounted) await _act('admin_set_statement_control', {..._params, 'p_receipt': r['receipt_number'], 'p_number': number, 'p_manual': true});
  }
  @override
  Widget build(BuildContext context) {
    final receipts = rows(_data?['receipts']).where(matches).toList();
    final reviews = rows(_data?['delivery_reviews']).where(matches).toList();
    final legacy = _data?['numbering_mode'] == 'legacy';
    final canEdit = _data?['can_edit'] == true && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('배송 확인 · 명세서 번호'), actions: [TextButton(onPressed: _busy ? null : _load, child: const Text('새로고침'))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Text('${widget.batch.routeLabel} · ${widget.batch.year} · V${widget.batch.voyage}'),
          if (legacy) const Text('기존 발행 번호 유지 · 고객 ID는 별도 표시', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('배송 매칭 확인 필요 ${_data?['review_count'] ?? 0}건', style: TextStyle(color: (_data?['review_count'] ?? 0) > 0 ? Colors.deepOrange : null, fontWeight: FontWeight.bold)),
          const Text('이름·전화번호 중 하나만 비슷하면 직접 확인합니다. 인쇄 전 번호를 잠그면 재연산에도 해당 번호가 유지됩니다.'),
          TextField(decoration: const InputDecoration(labelText: '고객명 · 고객 ID · 명세서 번호'), onChanged: (q) => setState(() => _query = q)),
          if (_data?['can_edit'] == true) Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Checkbox(value: receipts.isNotEmpty && receipts.every((r) => _selected.contains('${r['receipt_number']}')), onChanged: !canEdit ? null : (v) => setState(() { for (final r in receipts) { v == true ? _selected.add('${r['receipt_number']}') : _selected.remove('${r['receipt_number']}'); } })),
            const Text('표시된 명세서 전체 선택'),
            TextButton(onPressed: !canEdit || _selected.isEmpty ? null : () => _act('admin_set_statement_controls', {..._params, 'p_receipts': _selected.toList(), 'p_locked': true}), child: const Text('선택 번호 잠금')),
            TextButton(onPressed: !canEdit || _selected.isEmpty ? null : () => _act('admin_set_statement_controls', {..._params, 'p_receipts': _selected.toList(), 'p_locked': false}), child: const Text('선택 잠금 해제')),
          ]),
          if (_busy) const LinearProgressIndicator(),
          if (_error.isNotEmpty) Text(_error),
        ])),
        Expanded(child: _data == null && _error.isEmpty ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(12), children: [
          for (final r in reviews) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('배송 확인 필요 · ${r['name']}', style: const TextStyle(fontWeight: FontWeight.bold)), Text('${r['phone']}'),
            for (final c in rows(r['candidates'])) ...[
              const Divider(), Text('${c['name']} / ${c['receiver']}'), Text('${c['phone']} · ${c['type'] == 'province' ? '지방배송' : '시내배송'} · ${c['company']}'), Text('${c['address']}'), Text('${c['reason']}'),
              if (_data?['can_edit'] == true) Wrap(children: [
                for (final approved in [true, false]) TextButton(onPressed: !canEdit ? null : () => _act('admin_review_excel_delivery_match_scoped', {'p_year': widget.batch.year, 'p_voyage': widget.batch.voyage, 'p_route_key': _data!['route_key'], 'p_name': r['name'], 'p_phone': r['phone'], 'p_profile_id': c['id'], 'p_fingerprint': c['fingerprint'], 'p_approved': approved}), child: Text(approved ? '이 배송지로 확인' : '다른 고객 / 제외')),
              ]),
            ],
          ]))),
          for (final r in receipts) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text('${r['receipt_number']} · ${r['locked'] == true ? '번호 잠금' : r['manual'] == true ? '수동 지정' : legacy ? '기존 발행 번호' : '자동 번호'}'), value: _selected.contains('${r['receipt_number']}'), onChanged: !canEdit ? null : (v) => setState(() { v == true ? _selected.add('${r['receipt_number']}') : _selected.remove('${r['receipt_number']}'); })),
            Text('${r['name']} · ${(r['customer_codes'] as List? ?? []).join(', ')}'), Text('${r['phone']} · 화물 ${r['rows']}건'),
            if (_data?['can_edit'] == true) Wrap(children: [
              TextButton(onPressed: !canEdit || r['locked'] == true || r['data_locked'] == true ? null : () => _manual(r), child: const Text('수동 번호 지정')),
              TextButton(onPressed: !canEdit ? null : () => _act('admin_set_statement_control', {..._params, 'p_receipt': r['receipt_number'], 'p_locked': r['locked'] != true}), child: Text(r['locked'] == true ? '번호 잠금 해제' : '번호 잠금')),
              TextButton(onPressed: !canEdit || r['locked'] == true || r['data_locked'] == true || r['suggested_number'] == null ? null : () => _act('admin_set_statement_control', {..._params, 'p_receipt': r['receipt_number'], 'p_manual': false}), child: Text(legacy ? '기존 발행 번호 유지' : '고객 ID 자동 번호 (${r['suggested_number'] ?? '연결 확인 필요'})')),
            ]),
          ]))),
        ])),
      ]),
    );
  }
}
