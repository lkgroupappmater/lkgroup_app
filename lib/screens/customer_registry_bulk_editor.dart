import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/waybill_intake_text.dart';
import '../services/domestic_tracking_service.dart';

typedef RegistryRow = Map<String, dynamic>;

class CustomerRegistryBulkEditor extends StatefulWidget {
  const CustomerRegistryBulkEditor({super.key, required this.rows, required this.language, required this.merge, required this.callApi});
  final List<RegistryRow> rows;
  final AppLanguage language;
  final bool merge;
  final Future<RegistryRow> Function(String, RegistryRow) callApi;
  @override
  State<CustomerRegistryBulkEditor> createState() => _CustomerRegistryBulkEditorState();
}

class _CustomerRegistryBulkEditorState extends State<CustomerRegistryBulkEditor> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final Map<String, List<TextEditingController>> _fields = {};
  final Map<String, String> _targets = {};
  bool _busy = false, _reviewed = false;
  String? _message, _owner;
  String t(String k) => intakeText(widget.language, k);
  String label(RegistryRow c) => '${c['customer_code']} · ${c['name']} · ${c['phone']}';
  bool get valid => mounted && DomesticTrackingService.currentUserId == _owner;
  bool get mappingValid => _targets.entries.every((e) => _targets[e.value] == e.value);
  int get mergeCount => _targets.entries.where((e) => e.key != e.value).length;
  bool get changed => mergeCount > 0 || widget.rows.any((c) {
    if (_targets[c['id']] != c['id']) return false;
    final f = _fields[c['id']]!;
    return int.tryParse(f[0].text) != c['customer_no'] || f[1].text.trim() != c['name'] || f[2].text.trim() != c['phone'];
  });
  @override
  void initState() {
    super.initState(); _owner = DomesticTrackingService.currentUserId;
    for (final c in widget.rows) {
      final id = '${c['id']}'; _targets[id] = id;
      _fields[id] = [TextEditingController(text: '${c['customer_no']}'), TextEditingController(text: '${c['name']}'), TextEditingController(text: '${c['phone']}')];
    }
  }
  @override
  void dispose() { for (final f in _fields.values) { for (final c in f) { c.dispose(); } } _reason.dispose(); super.dispose(); }
  void _invalidate() => setState(() { _reviewed = false; _message = null; });
  Future<void> _save() async {
    if (_busy || !valid || !mappingValid || !changed || (mergeCount > 0 && !_reviewed) || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; });
    try {
      await widget.callApi('customers_bulk', {'confirmed': true, 'reason': _reason.text, 'rows': widget.rows.map((c) {
        final id = '${c['id']}', f = _fields[id]!;
        final keep = _targets[id] == id;
        return {'id': id, 'updated_at': c['updated_at'], 'target_id': _targets[id], 'customer_no': keep ? int.parse(f[0].text) : c['customer_no'], 'name': keep ? f[1].text.trim() : c['name'], 'phone': keep ? f[2].text.trim() : c['phone']};
      }).toList()});
      if (valid) { setState(() => _busy = false); Navigator.pop(context, true); }
    } catch (e) { if (valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'error')); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: Text(t(widget.merge ? 'bulkMerge' : 'bulkEdit'))),
    body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [
      Text('${t('selectedCustomers')}: ${widget.rows.length}'),
      if (widget.merge) ...[
        Text(t('bulkMergeHelp')), Text(t('mergeHelp')),
        DropdownButtonFormField<String>(key: const ValueKey('common-target'), isExpanded: true, decoration: InputDecoration(labelText: t('commonTarget')), hint: Text(t('chooseTarget')),
          items: widget.rows.map((c) => DropdownMenuItem(value: '${c['id']}', child: Text(label(c), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _busy ? null : (target) { if (target == null) return; setState(() { for (final c in widget.rows) { _targets['${c['id']}'] = [1,2].contains(c['customer_no']) ? '${c['id']}' : target; } _reviewed = false; }); }),
      ],
      for (final c in widget.rows) _row(c),
      TextFormField(controller: _reason, enabled: !_busy, maxLength: 500, decoration: InputDecoration(labelText: t('reason')), onChanged: (_) => _invalidate()),
      if (!mappingValid) Text(t('BULK_SELECTION_INVALID'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (widget.merge) ...[
        Text('${t('mergeCount')}: $mergeCount · ${t('sourceRows')}: ${widget.rows.where((c) => _targets[c['id']] != c['id']).fold<int>(0, (n,c) => n + ((c['source_count'] as num?)?.toInt() ?? 0))}'),
        CheckboxListTile(key: const ValueKey('bulk-reviewed'), contentPadding: EdgeInsets.zero, value: _reviewed, title: Text(t('bulkReviewed')), onChanged: _busy || !mappingValid || mergeCount == 0 ? null : (v) => setState(() => _reviewed = v ?? false)),
      ],
      if (_message != null) Text(_message!),
      if (_busy) const LinearProgressIndicator(),
      FilledButton(key: const ValueKey('bulk-save'), onPressed: _busy || !changed || !mappingValid || (mergeCount > 0 && !_reviewed) ? null : _save, child: Text(t('bulkSave'))),
    ])),
  ));
  Widget _row(RegistryRow c) {
    final id = '${c['id']}', f = _fields[id]!, keep = _targets[id] == id;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label(c), style: Theme.of(context).textTheme.titleMedium),
      Text('${t('sourceRows')}: ${c['source_count'] ?? 0}'),
      if (widget.merge) DropdownButtonFormField<String>(key: ValueKey('target-$id-${_targets[id]}'), initialValue: _targets[id], isExpanded: true, decoration: InputDecoration(labelText: t('keepId')),
        items: widget.rows.map((r) => DropdownMenuItem(value: '${r['id']}', child: Text(r['id'] == id ? '${t('keepSelf')} · ${r['customer_code']}' : label(r), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: _busy || [1,2].contains(c['customer_no']) ? null : (v) { if (v != null) setState(() { _targets[id] = v; _reviewed = false; }); }),
      TextFormField(key: ValueKey('number-$id'), controller: f[0], enabled: !_busy && keep, readOnly: widget.merge || [1,2].contains(c['customer_no']), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ID'), onChanged: (_) => _invalidate(), validator: (v) => !keep || ((int.tryParse(v ?? '') ?? 0) > 0 && (int.tryParse(v ?? '') ?? 0) < 1000000000) ? null : t('error')),
      TextFormField(key: ValueKey('name-$id'), controller: f[1], enabled: !_busy && keep, maxLength: 160, decoration: InputDecoration(labelText: t('receiver')), onChanged: (_) => _invalidate(), validator: (v) => !keep || (v ?? '').trim().isNotEmpty ? null : t('error')),
      TextFormField(key: ValueKey('phone-$id'), controller: f[2], enabled: !_busy && keep, maxLength: 40, decoration: InputDecoration(labelText: t('phone')), onChanged: (_) => _invalidate()),
    ])));
  }
}
