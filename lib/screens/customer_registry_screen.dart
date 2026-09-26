import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/waybill_intake_text.dart';
import '../services/domestic_tracking_service.dart';
import '../services/waybill_intake_service.dart';

typedef CustomerRow = Map<String, dynamic>;
List<CustomerRow> _maps(dynamic value) => (value as List? ?? []).map((v) => CustomerRow.from(v as Map)).toList();

class CustomerRegistryScreen extends StatefulWidget {
  const CustomerRegistryScreen({super.key, this.language = AppLanguage.korean, this.mismatchesOnly = false});
  final AppLanguage language;
  final bool mismatchesOnly;
  @override
  State<CustomerRegistryScreen> createState() => _CustomerRegistryScreenState();
}
class _CustomerRegistryScreenState extends State<CustomerRegistryScreen> {
  final _search = TextEditingController();
  List<CustomerRow> _rows = [];
  CustomerRow _summary = {};
  bool _busy = false, _conflicts = false, _mismatches = false, _more = false;
  int _page = 0, _total = 0;
  String? _message, _owner;
  String t(String k) => intakeText(widget.language, k);
  bool get valid => mounted && DomesticTrackingService.currentUserId == _owner;
  @override
  void initState() { super.initState(); _owner = DomesticTrackingService.currentUserId; _mismatches = widget.mismatchesOnly; _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await WaybillIntakeService.call('customers_list', {'page': _page, 'query': _search.text, 'conflicts_only': _conflicts, 'mismatches_only': _mismatches});
      if (valid) setState(() { _rows = _maps(r['customers']); _more = r['has_more'] == true; _total = (r['total'] as num).toInt(); _summary = CustomerRow.from(r['summary'] as Map? ?? {}); _message = null; });
    } catch (e) { if (valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'error')); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _edit(CustomerRow c) async {
    final number = TextEditingController(text: '${c['customer_no']}'), name = TextEditingController(text: '${c['name']}'), phone = TextEditingController(text: '${c['phone']}'), reason = TextEditingController();
    bool saving = false; String? message;
    await showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text(t('customers')), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: number, enabled: !saving, readOnly: [1,2].contains(c['customer_no']), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ID')),
        TextField(controller: name, enabled: !saving, maxLength: 160, decoration: InputDecoration(labelText: t('receiver'))),
        TextField(controller: phone, enabled: !saving, maxLength: 40, decoration: InputDecoration(labelText: t('phone'))),
        TextField(controller: reason, enabled: !saving, maxLength: 500, decoration: InputDecoration(labelText: t('reason'))),
        if (message != null) Text(message!),
      ])), actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: Text(t('close'))), FilledButton(onPressed: saving ? null : () async {
        final n = int.tryParse(number.text);
        if (n == null || n <= 0 || n >= 1000000000 || name.text.trim().isEmpty) { update(() => message = t('error')); return; }
        update(() => saving = true);
        try {
          await WaybillIntakeService.call('customers_update', {'id': c['id'], 'updated_at': c['updated_at'], 'customer_no': n, 'name': name.text, 'phone': phone.text, 'reason': reason.text});
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (valid) await _load();
        } catch (e) { if (dialogContext.mounted) update(() => message = t(e is DomesticTrackingException ? e.code : 'error')); }
        finally { if (dialogContext.mounted) update(() => saving = false); }
      }, child: Text(t('save')))],
    )));
    number.dispose(); name.dispose(); phone.dispose(); reason.dispose();
  }
  void _filter(bool duplicates, bool mismatches) { if (_busy) return; setState(() { _conflicts = duplicates; _mismatches = mismatches; _page = 0; }); _load(); }
  Future<void> _detail(CustomerRow c) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _RegistryDetail(id: '${c['id']}', language: widget.language)));
    if (valid) await _load();
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(t('customers')), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: t('refresh'))]), body: ListView(padding: const EdgeInsets.all(16), children: [
    Text(t('fixed')),
    Wrap(spacing: 8, runSpacing: 4, children: [
      ActionChip(label: Text('${t('total')} ${_summary['customers'] ?? 0}'), onPressed: () => _filter(false, false)),
      ActionChip(label: Text('${t('duplicates')} ${_summary['duplicate_customers'] ?? 0}'), onPressed: () => _filter(true, false)),
      ActionChip(backgroundColor: Colors.orange.shade100, label: Text('${t('mismatches')} ${_summary['mismatch_customers'] ?? 0}'), onPressed: () => _filter(false, true)),
    ]),
    Text('${t('mismatches')} · ${t('sourceRows')} ${_summary['mismatch_sources'] ?? 0}'),
    TextField(controller: _search, enabled: !_busy, decoration: InputDecoration(labelText: 'ID / ${t('receiver')} / ${t('phone')}'), onSubmitted: (_) { _page = 0; _load(); }),
    CheckboxListTile(contentPadding: EdgeInsets.zero, value: _conflicts, title: Text(t('duplicates')), onChanged: _busy ? null : (v) => _filter(v ?? false, _mismatches)),
    CheckboxListTile(contentPadding: EdgeInsets.zero, value: _mismatches, title: Text(t('mismatches')), onChanged: _busy ? null : (v) => _filter(_conflicts, v ?? false)),
    Wrap(spacing: 8, children: [OutlinedButton(onPressed: _busy ? null : () { _page = 0; _load(); }, child: Text(t('search'))), TextButton(onPressed: _busy ? null : () { _search.clear(); _filter(false, false); }, child: Text(t('reset')))]),
    if (_busy) const LinearProgressIndicator(), if (_message != null) Text(_message!), Text('${t('total')} $_total'),
    for (final c in _rows) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${c['customer_code']} · ${c['name']}', style: Theme.of(context).textTheme.titleMedium), Text('${c['phone']}'),
      Text('${t('sourceRows')} ${c['source_count']} · ${t('duplicates')} ${(c['duplicates'] as List? ?? []).length} · ${t('mismatches')} ${c['mismatch_count'] ?? 0}'),
      Wrap(spacing: 8, children: [TextButton(onPressed: _busy ? null : () => _edit(c), child: Text(t('edit'))), TextButton(onPressed: _busy ? null : () => _detail(c), child: Text(t('reviewStatus')))]),
    ]))),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [TextButton(onPressed: _busy || _page == 0 ? null : () { _page--; _load(); }, child: Text(t('prev'))), TextButton(onPressed: _busy || !_more ? null : () { _page++; _load(); }, child: Text(t('more')))]),
  ]));
}

class _RegistryDetail extends StatefulWidget {
  const _RegistryDetail({required this.id, required this.language});
  final String id;
  final AppLanguage language;
  @override
  State<_RegistryDetail> createState() => _RegistryDetailState();
}
class _RegistryDetailState extends State<_RegistryDetail> {
  CustomerRow? _data;
  String? _owner, _message;
  bool _busy = false;
  int _shown = 100;
  String t(String k) => intakeText(widget.language, k);
  bool get valid => mounted && DomesticTrackingService.currentUserId == _owner;
  @override
  void initState() { super.initState(); _owner = DomesticTrackingService.currentUserId; _load(); }
  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try { final r = await WaybillIntakeService.call('customers_detail', {'id': widget.id}); if (valid) setState(() { _data = r; _message = null; }); }
    catch (e) { if (valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'error')); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<CustomerRow?> _choose({bool includeSelf = false}) async {
    final search = TextEditingController(); String query = '';
    final choices = _maps(_data?['choices']).where((c) => includeSelf || c['id'] != widget.id).toList();
    final result = await showDialog<CustomerRow>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) {
      final filtered = choices.where((c) => [c['customer_code'], c['name'], c['phone']].any((v) => '$v'.toLowerCase().contains(query))).toList();
      return AlertDialog(title: Text(t('findTarget')), content: SizedBox(width: 500, height: 400, child: Column(children: [
        TextField(controller: search, decoration: InputDecoration(labelText: t('search')), onSubmitted: (_) => update(() => query = search.text.trim().toLowerCase())),
        TextButton(onPressed: () => update(() => query = search.text.trim().toLowerCase()), child: Text(t('search'))),
        Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) { final c = filtered[i]; return ListTile(title: Text('${c['customer_code']} · ${c['name']}'), subtitle: Text('${c['phone']}'), onTap: () => Navigator.pop(context, c)); })),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t('close')))]);
    }));
    search.dispose(); return result;
  }
  Future<void> _merge(CustomerRow choice) async {
    if (_busy) return;
    setState(() => _busy = true);
    CustomerRow target;
    try { final r = await WaybillIntakeService.call('customers_detail', {'id': choice['id']}); target = CustomerRow.from(r['customer'] as Map); }
    catch (e) { if (valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'error')); if (mounted) setState(() => _busy = false); return; }
    if (!valid) return;
    final source = CustomerRow.from(_data!['customer']); bool checked = false, saving = false; String? message;
    final merged = await showDialog<bool>(context: context, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text(t('mergePreview')), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${t('fromId')}: ${source['customer_code']} · ${source['name']} · ${source['phone']} (${source['source_count']})'),
        Text('${t('keepId')}: ${target['customer_code']} · ${target['name']} · ${target['phone']} (${target['source_count']})'),
        Text('${t('mergedTotal')}: ${(source['source_count'] as num) + (target['source_count'] as num)}'), Text(t('mergeHelp')),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: checked, title: Text(t('sameCustomer')), onChanged: saving ? null : (v) => update(() => checked = v ?? false)),
        if (message != null) Text(message!),
      ])), actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: Text(t('close'))), FilledButton(onPressed: !checked || saving ? null : () async {
        update(() => saving = true);
        try { await WaybillIntakeService.call('customers_merge', {'source_id': source['id'], 'target_id': target['id'], 'source_updated_at': source['updated_at'], 'target_updated_at': target['updated_at'], 'confirmed': true}); if (dialogContext.mounted) Navigator.pop(dialogContext, true); }
        catch (e) { if (dialogContext.mounted) update(() => message = t(e is DomesticTrackingException ? e.code : 'error')); }
        finally { if (dialogContext.mounted) update(() => saving = false); }
      }, child: Text(t('merge')))],
    )));
    if (valid) { setState(() => _busy = false); if (merged == true) Navigator.pop(context); }
  }
  Future<void> _resolve(CustomerRow source) async {
    final target = await _choose(includeSelf: true); if (target == null || !valid) return;
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(t('resolveSource')), content: Text('${source['name']} · ${source['phone']}\n${t('keepId')}: ${target['customer_code']} · ${target['name']} · ${target['phone']}\n\n${t('sourceHelp')}'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('close'))), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('save')))]));
    if (confirm != true || !valid) return;
    setState(() => _busy = true);
    try { await WaybillIntakeService.call('customers_resolve_source', {'source_kind': source['source_kind'], 'source_id': source['source_id'], 'from_id': widget.id, 'target_id': target['id'], 'name': source['name'], 'phone': source['phone'], 'confirmed': true}); if (valid) { setState(() => _busy = false); await _load(); } }
    catch (e) { if (valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'error')); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final c = _data?['customer'] as Map?;
    final sources = _maps(_data?['sources'])..sort((a,b) => (b['mismatch'] == true ? 1 : 0).compareTo(a['mismatch'] == true ? 1 : 0));
    final candidates = _maps(_data?['candidates']);
    return Scaffold(appBar: AppBar(title: Text(t('reviewStatus')), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: t('refresh'))]), body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_busy) const LinearProgressIndicator(), if (_message != null) Text(_message!),
      if (c != null) ...[
        Text('${c['customer_code']} · ${c['name']} · ${c['phone']}', style: Theme.of(context).textTheme.titleLarge), Text(t('mergeHelp')),
        if (candidates.isEmpty) Text(t('noCandidates')),
        for (final d in candidates) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${d['customer_code']} · ${d['name']} · ${d['phone']}'), Text((d['reasons'] as List).map((k) => t('$k')).join(' / ')), TextButton(onPressed: _busy ? null : () => _merge(d), child: Text(t('keepId')))]))),
        OutlinedButton(onPressed: _busy ? null : () async { final target = await _choose(); if (target != null && valid) await _merge(target); }, child: Text(t('findTarget'))),
        const SizedBox(height: 16), Text('${t('sourceRows')} (${sources.length})', style: Theme.of(context).textTheme.titleLarge), Text(t('sourceHelp')),
        for (final s in sources.take(_shown)) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (s['mismatch'] == true) Text(t('mismatches'), style: TextStyle(color: Colors.deepOrange.shade800, fontWeight: FontWeight.bold)),
          Text('${s['label']}'), Text('${s['name']} · ${s['phone']}'),
          if (s['mismatch'] == true) TextButton(onPressed: _busy ? null : () => _resolve(s), child: Text(t('resolveSource'))),
        ]))),
        if (sources.length > _shown) TextButton(onPressed: () => setState(() => _shown += 100), child: Text(t('more'))),
      ],
    ]));
  }
}
