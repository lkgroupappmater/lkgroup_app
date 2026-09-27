import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/waybill_intake_text.dart';
import '../services/domestic_tracking_service.dart';

typedef AutoMergeRow = Map<String, dynamic>;

class CustomerRegistryAutoMerge extends StatefulWidget {
  const CustomerRegistryAutoMerge({super.key, required this.language, required this.callApi});
  final AppLanguage language;
  final Future<AutoMergeRow> Function(String, AutoMergeRow) callApi;
  @override
  State<CustomerRegistryAutoMerge> createState() => _CustomerRegistryAutoMergeState();
}

class _CustomerRegistryAutoMergeState extends State<CustomerRegistryAutoMerge> {
  List<AutoMergeRow> _groups = [];
  final Set<String> _selected = {};
  AutoMergeRow? _preview;
  String? _owner, _message;
  bool _busy = false, _reviewed = false;
  String t(String key) => intakeText(widget.language, key);
  bool get valid => mounted && DomesticTrackingService.currentUserId == _owner;
  List<AutoMergeRow> rows(dynamic value) => (value as List? ?? []).map((v) => AutoMergeRow.from(v as Map)).toList();
  @override
  void initState() { super.initState(); _owner = DomesticTrackingService.currentUserId; _load(); }
  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final data = await widget.callApi('customers_auto_candidates', {});
      if (!valid) return;
      setState(() {
        _groups = rows(data['groups']); _selected.clear();
        for (final g in _groups) { if (g['default_selected'] == true) { for (final c in rows(g['members'])) { _selected.add('${c['id']}'); } } }
      });
    } catch (e) { if (valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'error')); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _prepare() async {
    if (_busy || !valid) return;
    setState(() { _busy = true; _message = null; _reviewed = false; });
    try {
      final selection = _groups.expand((g) => rows(g['members'])).where((c) => _selected.contains(c['id'])).map((c) => {'id': c['id'], 'updated_at': c['updated_at']}).toList();
      final result = await widget.callApi('customers_auto_preview', {'selection': selection});
      if (valid) setState(() => _preview = result);
    } catch (e) { if (valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'error')); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _commit() async {
    if (_busy || !_reviewed || _preview == null || !valid) return;
    setState(() { _busy = true; _message = null; });
    try {
      // Send only the exact members displayed in the final preview.
      final selection = rows(_preview!['groups']).expand((g) => rows(g['members'])).map((c) => {'id': c['id'], 'updated_at': c['updated_at']}).toList();
      await widget.callApi('customers_auto_commit', {'selection': selection, 'confirmed': true});
      if (valid) { setState(() => _busy = false); Navigator.pop(context, true); }
    } catch (e) { if (valid) setState(() { _reviewed = false; _message = t(e is DomesticTrackingException ? e.code : 'error'); }); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: Text(t('autoMerge'))),
    body: Column(children: [
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(t('deliveryMergeReminder'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), Text(t('autoMergeHelp')),
        if (_message != null) Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_preview == null) ...[
          if (!_busy && _groups.isEmpty) Text(t('noCandidates')),
          for (final g in _groups) Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t('selectedCustomers')}: ${rows(g['members']).where((c) => _selected.contains(c['id'])).length} / ${rows(g['members']).length}'),
            if (g['protected_group'] == true) Text(t('protectedIdentity'), style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final c in rows(g['members'])) CheckboxListTile(
              key: ValueKey('auto-select-${c['id']}'), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(c['id']),
              title: Text('${c['customer_code']} · ${c['name']}'),
              subtitle: Text('${c['phone']}\n${(c['delivery_contexts'] as List? ?? []).isEmpty ? t('noDeliveryInfo') : (c['delivery_contexts'] as List).join('\n')}'),
              onChanged: _busy ? null : (v) => setState(() { if (v == true) { _selected.add('${c['id']}'); } else { _selected.remove(c['id']); } _reviewed = false; }),
            ),
          ]))),
        ] else ...[
          Text('${t('mergeCount')}: ${_preview!['merged_count']}'),
          if ((_preview!['excluded_count'] as num? ?? 0) > 0) Text('${t('autoExcluded')}: ${_preview!['excluded_count']}'),
          for (final g in rows(_preview!['groups'])) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t('fromId')}: ${rows(g['members']).map((c) => c['customer_code']).join(', ')}'),
            Text('${t('keepId')}: ${g['customer_code']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${g['name']}'), Text('${g['phone']}'),
          ]))),
          CheckboxListTile(key: const ValueKey('auto-reviewed'), contentPadding: EdgeInsets.zero, value: _reviewed, title: Text(t('autoReviewConfirm')), onChanged: _busy ? null : (v) => setState(() => _reviewed = v ?? false)),
        ],
      ])),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_preview != null) TextButton(onPressed: _busy ? null : () => setState(() { _preview = null; _reviewed = false; _message = null; }), child: Text(t('autoBack'))),
        SizedBox(width: double.infinity, child: FilledButton(key: const ValueKey('auto-submit'), onPressed: _busy ? null : _preview == null ? (_selected.length >= 2 ? _prepare : null) : (_reviewed ? _commit : null), child: Text(t(_preview == null ? 'autoPreview' : 'autoCommit')))),
      ]))),
    ]),
  ));
}
