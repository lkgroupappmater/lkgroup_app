import '../services/shared_ui_text_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../core/domestic_tracking_text.dart';
import '../core/route_catalog.dart';
import '../models/app_user.dart';
import '../services/domestic_tracking_service.dart';
import '../services/shipment_filter_options_service.dart';

class DomesticTrackingScreen extends StatefulWidget {
  const DomesticTrackingScreen({
    super.key,
    required this.language,
    this.user,
    this.manage = false,
    this.loadFilterBatches,
    this.callApi,
  });
  final AppLanguage language;
  final AppUser? user;
  final bool manage;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? callApi;
  final Future<List<ShipmentBatchOption>> Function()? loadFilterBatches;
  @override
  State<DomesticTrackingScreen> createState() => _DomesticTrackingScreenState();
}

class _DomesticTrackingScreenState extends State<DomesticTrackingScreen> with WidgetsBindingObserver, SharedUiTextState {
  final _number = TextEditingController();
  String _carrier = '', _queryType = 'statement';
  String _route = '', _year = '', _voyage = '';
  String _mode = 'statement_lookup';
  Map<String, dynamic> _submitted = {};
  List<ShipmentBatchOption> _batches = [];
  bool _filtersLoading = false, _filtersFailed = false;
  bool _busy = false, _more = false;
  int _page = 0;
  String? _message;
  List<Map<String, dynamic>> _rows = [];
  Timer? _refreshTimer;
  bool _foreground = true;
  String? _owner;
  bool get _valid => mounted && widget.user?.id == _owner && (widget.callApi != null || DomesticTrackingService.currentUserId == _owner);
  String t(String k) => domesticText(widget.language, k);
  bool get manager =>
      [UserRole.admin, UserRole.staff].contains(widget.user?.role);
  bool get isOperator => manager || widget.user?.role == UserRole.partner;
  String error(Object e) =>
      t(e is DomesticTrackingException ? e.code : 'REQUEST_FAILED');
  @override
  void initState() {
    super.initState();
    _owner = widget.user?.id;
    WidgetsBinding.instance.addObserver(this);
    if (widget.manage && isOperator) _list();
    if (widget.user != null) _loadFilters();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(covariant DomesticTrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?.id != widget.user?.id) {
      _rows = []; _submitted = {}; _more = false; _page = 0;
      _owner = widget.user?.id;
    }
  }

  Future<void> _loadFilters() async {
    if (_filtersLoading) return;
    final owner = widget.user?.id;
    setState(() { _filtersLoading = true; _filtersFailed = false; });
    try {
      final rows = await (widget.loadFilterBatches?.call() ??
          ShipmentFilterOptionsService.instance.listBatches());
      if (mounted && widget.user?.id == owner) setState(() {
        _batches = rows.where((r) => r.route.trim().isNotEmpty &&
            r.year >= 1900 && r.year <= 2200 && r.voyage.trim().isNotEmpty).toList();
      });
    } catch (_) {
      if (mounted && widget.user?.id == owner) setState(() => _filtersFailed = true);
    } finally {
      if (mounted) setState(() => _filtersLoading = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _number.dispose();
    super.dispose();
  }

  Future<void> _run(String action, Map<String, dynamic> args, {bool quiet = false}) async {
    if (_busy || !_valid) return;
    final requestOwner = _owner;
    setState(() {
      _busy = true;
      if (!quiet) { _message = t('loading'); _rows = []; _more = false; }
      if (action == 'lookup') _page = 0;
    });
    try {
      final data = await (widget.callApi?.call(action, {...args, 'grouped': true}) ?? DomesticTrackingService.call(action, {...args, 'grouped': true}));
      if (!_valid || requestOwner != _owner) return;
      setState(() {
        _rows = (data['parcels'] as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
        if (_rows.isNotEmpty) _refreshTimer ??= Timer.periodic(const Duration(minutes: 5), (_) {
          if (_valid && _foreground && _rows.isNotEmpty && ModalRoute.of(context)?.isCurrent == true) _loadPage(quiet: true);
        });
        _more = data['has_more'] == true;
        _message = _rows.isEmpty
            ? t((data['cargo_count'] as num? ?? 0) > 0 ? 'noLinked' : 'empty')
            : null;
      });
    } catch (e) {
      if (_valid && requestOwner == _owner) setState(() => _message = error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _list() {
    _mode = 'list_groups';
    return _run('list_groups', {'page': _page});
  }
  Future<void> _loadPage({bool quiet = false}) => _run(_mode, {...(_mode == 'list_groups' ? <String, dynamic>{} : _submitted), 'page': _page}, quiet: quiet);
  Future<void> _lookup([Map<String, dynamic>? row]) {
    if (row != null) {
      return _loadPage();
    }
    _page = 0;
    _mode = _queryType == 'tracking' ? 'lookup' : _queryType == 'statement' ? 'statement_lookup' : 'reference_lookup';
    _submitted = _queryType == 'tracking' ? {'carrier': _carrier, 'tracking_number': _number.text}
      : _queryType == 'statement' ? {'statement_number': _number.text.trim(), 'route': _route, 'shipment_year': _year, 'voyage': _voyage}
      : {'reference_type': _queryType, 'reference_number': _number.text.trim()};
    return _loadPage();
  }
  Future<void> _edit([Map<String, dynamic>? row, Map<String, dynamic>? linkSource]) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            DomesticWaybillEditor(language: widget.language, row: row, linkSource: linkSource),
      ),
    );
    if (result != null && mounted) {
      if (_mode == 'statement_lookup' && _submitted.isEmpty) { await _list(); } else { await _loadPage(); }
    }
  }

  Future<void> _addEvent(Map<String, dynamic> row) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            DomesticEventEditor(language: widget.language, row: row),
      ),
    );
    if (result != null && mounted) await _lookup(result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t(widget.manage ? 'manage' : 'title'))),
    body: widget.user == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t('LOGIN_REQUIRED')),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t(widget.manage ? 'manageHint' : 'hint')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(initialValue: _queryType, isExpanded: true,
                decoration: InputDecoration(labelText: t('lookupKind')),
                items: [for (final pair in [['statement','linkStatement'],['ecommerce','ecommerce'],['local','local'],['tracking','tracking']]) DropdownMenuItem(value: pair[0], child: Text(t(pair[1])))],
                onChanged: _busy ? null : (v) => setState(() => _queryType = v!)),
              const SizedBox(height: 12),
              if (_queryType == 'statement') _filters(),
              if (_queryType == 'tracking') DropdownButtonFormField<String>(
                initialValue: _carrier,
                isExpanded: true,
                decoration: InputDecoration(labelText: t('carrier')),
                items: [
                  DropdownMenuItem(value: '', child: Text(t('all'))),
                  ...DomesticTrackingService.carriers.entries.map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _carrier = v ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _number,
                maxLength: _queryType == 'tracking' ? 40 : 80,
                decoration: InputDecoration(labelText: t(_queryType == 'tracking' ? 'tracking' : _queryType == 'statement' ? 'statement' : 'referenceNumber')),
                onSubmitted: _busy ? null : (_) => _lookup(),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _lookup(),
                icon: const Icon(Icons.search),
                label: Text(t('search')),
              ),
              if (isOperator)
                Wrap(
                  spacing: 10,
                  children: [
                    if (isOperator)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _edit(),
                        icon: const Icon(Icons.add),
                        label: Text(t('add')),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              _page = 0;
                              _list();
                            },
                      child: Text(t('list')),
                    ),
                  ],
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_message!, semanticsLabel: _message),
                ),
              if (_rows.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t('autoRefreshHint'))),
              ..._groups(),
              if (_page > 0 || _more)
                Wrap(
                  spacing: 12,
                  children: [
                    if (_page > 0)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _page--;
                                _loadPage();
                              },
                        child: Text(t('prev')),
                      ),
                    if (_more)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _page++;
                                _loadPage();
                              },
                        child: Text(t('more')),
                      ),
                  ],
                ),
            ],
          ),
  );
  Widget _filters() {
    final routes = _batches.map((b) => b.route).toSet().toList()..sort();
    final years = _batches.where((b) => _route.isEmpty || b.route == _route)
        .map((b) => b.year.toString()).toSet().toList()..sort((a,b) => b.compareTo(a));
    final voyages = _batches.where((b) => (_route.isEmpty || b.route == _route) &&
        (_year.isEmpty || b.year.toString() == _year)).map((b) => b.voyage).toSet().toList()
      ..sort((a, b) {
        final an = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? -1;
        final bn = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? -1;
        return an == bn ? a.compareTo(b) : bn.compareTo(an);
      });
    Widget select(String key, String value, List<String> values, ValueChanged<String> onChanged) =>
        Padding(padding: const EdgeInsets.only(bottom: 12), child: DropdownButtonFormField<String>(
          key: ValueKey('$key-$value-${values.join(',')}'), initialValue: value,
          isExpanded: true, decoration: InputDecoration(labelText: t(key)),
          items: [DropdownMenuItem(value: '', child: Text(t('any'))),
            ...values.map((v) => DropdownMenuItem(value: v,
              child: Text(key == 'route' ? RouteCatalog.localizedLabel(v, widget.language) : v)))],
          onChanged: _busy || _filtersLoading || values.isEmpty ? null : (v) => setState(() => onChanged(v ?? '')),
        ));
    return Column(children: [
      if (_filtersLoading) Text(t('filtersLoading')),
      if (_filtersFailed) Row(children: [
        Expanded(child: Text(t('filtersFailed'))),
        TextButton(onPressed: _busy ? null : _loadFilters, child: Text(t('retry'))),
      ]),
      if (!_filtersLoading && !_filtersFailed && _batches.isEmpty) Text(t('filtersEmpty')),
      select('route', _route, routes, (v) { _route = v; _year = ''; _voyage = ''; }),
      select('year', _year, years, (v) { _year = v; _voyage = ''; }),
      select('voyage', _voyage, voyages, (v) => _voyage = v),
    ]);
  }
  List<Widget> _groups() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      final key = '${row['group_key'] ?? row['id']}';
      (groups[key] ??= []).add(row);
    }
    return groups.entries.map((entry) {
      final rows = entry.value, first = rows.first;
      final statement = first['statement'] ?? first['cargo'];
      final title = statement is Map ? '${t('statementNumber')}: ${statement['receipt_number'] ?? statement['box_number']}'
          : first['reference_number'] != null ? '${t('${first['reference_type']}')}: ${first['reference_number']}' : t('linkLegacy');
      final photos = <String>{};
      for (final row in rows) {
        photos.addAll((row['photo_urls'] as List? ?? [if (row['photo_url'] != null) row['photo_url']]).cast<String>());
      }
      return Card(key: ValueKey('statement-group-${entry.key}'), margin: const EdgeInsets.symmetric(vertical: 12),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(title, style: Theme.of(context).textTheme.titleLarge),
          if (statement is Map) Text('${RouteCatalog.localizedLabel('${statement['route']}', widget.language)} · ${statement['shipment_year']} / ${statement['voyage']}'),
          Text('${t('waybillCount')}: ${rows.length}'),
          if (isOperator) TextButton.icon(onPressed: _busy ? null : () => _edit(null, first), icon: const Icon(Icons.add), label: Text(t('addWaybill'))),
          const SizedBox(height: 12),
          Text(t('photo'), style: Theme.of(context).textTheme.titleSmall),
          if (photos.isEmpty) Text(t(rows.any((r) => r['photo_restricted'] == true) ? 'restricted' : 'noPhoto')),
          Wrap(spacing: 12, runSpacing: 12, children: photos.map(_photoView).toList()),
          ...rows.map(_card),
        ])));
    }).toList();
  }

  Widget _photoView(String url) => InkWell(
    onTap: () => showDialog<void>(context: context, builder: (dialogContext) => Dialog(child: Stack(children: [
      InteractiveViewer(child: Image.network(url, errorBuilder: (_, __, ___) => Text(t('REQUEST_FAILED')))),
      Positioned(right: 0, top: 0, child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(dialogContext))),
    ]))),
    child: Image.network(url, height: 160, width: 180, fit: BoxFit.contain, errorBuilder: (_, __, ___) => SizedBox(width: 180, child: Text(t('REQUEST_FAILED')))));

  Widget _card(Map<String, dynamic> r) {
    final integration = r['integration'];
    final notice = ['planned', 'connection_required'].contains(integration)
        ? t('connection')
        : integration == 'verification_required'
        ? t('verify')
        : r['sync_state'] == 'error'
        ? t('failed')
        : null;
    final events = (r['events'] as List? ?? []).cast<Map>();
    final cargo = r['cargo'];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r['carrier_name']} · ${t(r['delivery_kind'])} · ${t(r['service_kind'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            SelectableText(
              '${r['tracking_number']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Chip(label: Text(t(r['status']))),
            ),
            if (cargo is Map)
              Text(
                '${cargo['receipt_number'] ?? cargo['invoice_number'] ?? cargo['box_number']} · ${cargo['box_number']}\n${RouteCatalog.localizedLabel('${cargo['route'] ?? ''}', widget.language)} · ${cargo['shipment_year']} / ${cargo['voyage']}',
              ),
            const SizedBox(height: 12),
            if ('${r['receiver_name'] ?? ''}'.isNotEmpty) Text('${t('receiver')}: ${r['receiver_name']}'),
            if ('${r['receiver_phone'] ?? ''}'.isNotEmpty) Text('${t('phone')}: ${r['receiver_phone']}'),
            if (r['recipient_masked'] == true) Text(t('recipientMasked'), style: Theme.of(context).textTheme.bodySmall),
            if ('${r['origin']}${r['destination']}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('${r['origin']} → ${r['destination']}'),
              ),
            Text(
              '${t('synced')}: ${DomesticTrackingService.laoDate(r['synced_at'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '${t('checked')}: ${DomesticTrackingService.laoDate(r['checked_at'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (notice != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(12),
                color: Colors.amber.shade50,
                child: Text(notice),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _lookup(r),
                  child: Text(t('refresh')),
                ),
                if (r['official_url'] != null)
                  TextButton(
                    onPressed: () async {
                      final ok = await launchUrl(
                        Uri.parse(r['official_url']),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!ok && mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(t('REQUEST_FAILED'))),
                        );
                    },
                    child: Text(t('official')),
                  ),
                if (r['can_manage'] == true) ...[
                  TextButton(
                    onPressed: _busy ? null : () => _edit(r),
                    child: Text(t('edit')),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _addEvent(r),
                    child: Text(t('manual')),
                  ),
                ],
              ],
            ),
            Text(t('history'), style: Theme.of(context).textTheme.titleMedium),
            Text(t('timezone'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (events.isEmpty) Text(t('noEvents')),
            ...events.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3, right: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xff315b9c),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DomesticTrackingService.laoDate(e['occurred_at']),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '${e['location'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text('${e['description'] ?? ''}'),
                          Text(
                            '${t(e['source'] == 'staff' ? 'staff' : 'carrierSource')} · ${t(e['status'])}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DomesticPhotoSelection {
  const DomesticPhotoSelection(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class _WaybillDraft {
  final number = TextEditingController();
  String carrier = '';
  bool chosen = false;
}

class DomesticWaybillEditor extends StatefulWidget {
  const DomesticWaybillEditor({super.key, required this.language, this.row,
    this.loadFilterBatches, this.callApi, this.linkSource, this.pickPhotos});
  final AppLanguage language;
  final Map<String, dynamic>? row;
  final Map<String, dynamic>? linkSource;
  final Future<List<DomesticPhotoSelection>> Function()? pickPhotos;
  final Future<List<ShipmentBatchOption>> Function()? loadFilterBatches;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? callApi;
  @override
  State<DomesticWaybillEditor> createState() => _DomesticWaybillEditorState();
}

class _DomesticWaybillEditorState extends State<DomesticWaybillEditor> with SharedUiTextState {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController(), _name = TextEditingController(),
    _phone = TextEditingController(), _cargoQuery = TextEditingController(),
    _receipt = TextEditingController(), _reference = TextEditingController();
  String _carrier = '', _kind = 'province', _service = 'domestic';
  String _scope = 'statement', _referenceType = 'ecommerce';
  String _route = '', _year = '', _voyage = '';
  bool _carrierChosen = false, _busy = false, _finding = false;
  bool _filtersLoading = false, _filtersFailed = false;
  int _lookupVersion = 0;
  int? _cargo, _cargoCount;
  Map<String, dynamic>? _confirmed;
  List<Map<String, dynamic>> _cargoRows = [];
  List<ShipmentBatchOption> _batches = [];
  final List<_WaybillDraft> _extraWaybills = [];
  final List<DomesticPhotoSelection> _photos = [];
  bool _picking = false;
  String? _message, _owner;
  String t(String key) => domesticText(widget.language, key);
  bool get _valid => mounted && (widget.callApi != null || DomesticTrackingService.currentUserId == _owner);
  Future<Map<String, dynamic>> _call(String action, Map<String, dynamic> body) {
    if (!_valid) throw const DomesticTrackingException('LOGIN_REQUIRED');
    return widget.callApi?.call(action, body) ?? DomesticTrackingService.call(action, body);
  }
  @override
  void initState() {
    super.initState();
    _owner = DomesticTrackingService.currentUserId;
    final row = widget.row ?? widget.linkSource;
    if (row != null) {
      _kind = '${row['delivery_kind']}'; _service = '${row['service_kind']}';
      if (widget.row != null) { _carrier = '${row['carrier']}'; _number.text = '${row['tracking_number']}'; }
      _name.text = '${row['receiver_name'] ?? ''}'; _phone.text = '${row['receiver_phone'] ?? ''}';
      _cargo = (row['shipment_id'] as num?)?.toInt();
      _scope = '${row['link_scope'] ?? (_cargo == null ? 'standalone' : 'cargo')}';
      _referenceType = '${row['reference_type'] ?? 'ecommerce'}';
      _reference.text = '${row['reference_number'] ?? ''}'; _carrierChosen = widget.row != null;
      if (row['cargo'] is Map) _cargoRows = [Map<String, dynamic>.from(row['cargo'])];
      if (_scope == 'statement' && row['statement'] is Map) {
        _confirmed = Map<String, dynamic>.from(row['statement']);
        _route = '${_confirmed!['route']}'; _year = '${_confirmed!['shipment_year']}';
        _voyage = '${_confirmed!['voyage']}'; _receipt.text = '${_confirmed!['receipt_number']}';
      }
    }
    _loadBatches();
  }
  @override
  void dispose() {
    for (final c in [_number, _name, _phone, _cargoQuery, _receipt, _reference, ..._extraWaybills.map((w) => w.number)]) { c.dispose(); }
    super.dispose();
  }
  Future<void> _loadBatches() async {
    if (_filtersLoading) return;
    setState(() { _filtersLoading = true; _filtersFailed = false; });
    try {
      final rows = await (widget.loadFilterBatches?.call() ?? ShipmentFilterOptionsService.instance.listBatches());
      if (_valid) setState(() {
        _batches = rows.where((r) => r.route.trim().isNotEmpty && r.voyage.trim().isNotEmpty && r.year >= 1900 && r.year <= 2200).toList();
        if (!_batches.any((r) => r.route == _route)) { _route = ''; _year = ''; _voyage = ''; _invalidate(); }
        if (!_batches.any((r) => r.route == _route && '${r.year}' == _year)) { _year = ''; _voyage = ''; _invalidate(); }
        if (!_batches.any((r) => r.route == _route && '${r.year}' == _year && r.voyage == _voyage)) { _voyage = ''; _invalidate(); }
      });
    } catch (_) { if (_valid) setState(() => _filtersFailed = true); }
    finally { if (mounted) setState(() => _filtersLoading = false); }
  }
  void _invalidate() { _lookupVersion++; _confirmed = null; _cargoCount = null; _message = null; }
  Future<void> _confirmStatement() async {
    if (_busy || _finding) return;
    if ([_route, _year, _voyage, _receipt.text.trim()].any((v) => v.isEmpty)) {
      setState(() => _message = t('STATEMENT_REQUIRED')); return;
    }
    final version = ++_lookupVersion;
    setState(() { _finding = true; _confirmed = null; _message = null; });
    try {
      final data = await _call('statement_resolve', {'route': _route, 'shipment_year': _year, 'voyage': _voyage, 'receipt_number': _receipt.text.trim()});
      if (!_valid || version != _lookupVersion) return;
      setState(() {
        if (data['statement'] == null) { _message = t('STATEMENT_NOT_FOUND'); return; }
        _confirmed = Map<String, dynamic>.from(data['statement']);
        _receipt.text = '${_confirmed!['receipt_number']}'; _cargoCount = (data['cargo_count'] as num?)?.toInt();
        final cargo = data['cargo'] as List? ?? [];
        _name.text = cargo.isEmpty ? '' : '${cargo.first['consignee_name'] ?? ''}';
        _phone.text = cargo.isEmpty ? '' : '${cargo.first['consignee_phone'] ?? ''}';
      });
    } catch (e) { if (_valid && version == _lookupVersion) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'REQUEST_FAILED')); }
    finally { if (mounted) setState(() => _finding = false); }
  }
  Future<void> _findCargo() async {
    if (_finding || _busy) return;
    final version = ++_lookupVersion; setState(() => _finding = true);
    try {
      final data = await _call('cargo_search', {'query': _cargoQuery.text});
      if (_valid && version == _lookupVersion) setState(() {
        _cargo = null; _cargoRows = (data['cargo'] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _message = _cargoRows.isEmpty ? t('empty') : null;
      });
    } catch (e) { if (_valid && version == _lookupVersion) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'REQUEST_FAILED')); }
    finally { if (mounted) setState(() => _finding = false); }
  }
  Future<void> _pick() async {
    if (_picking || _busy) return;
    setState(() => _picking = true);
    try {
      final selected = <DomesticPhotoSelection>[];
      final existing = (widget.row?['photo_count'] as num?)?.toInt() ?? (widget.row?['photo_url'] == null ? 0 : 1);
      if (widget.pickPhotos != null) {
        selected.addAll(await widget.pickPhotos!());
      } else {
        final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
        if (existing + _photos.length + files.length > 10) throw const DomesticTrackingException('TOO_MANY_PHOTOS');
        var total = _photos.fold<int>(0, (n, p) => n + p.bytes.length);
        for (final file in files) {
          final size = await file.length();
          if (size > 5242880 || total + size > 15728640) throw const DomesticTrackingException('FILE_TOO_LARGE');
          final bytes = await file.readAsBytes(); total += bytes.length;
          selected.add(DomesticPhotoSelection(file.name, bytes));
        }
      }
      if (existing + _photos.length + selected.length > 10) throw const DomesticTrackingException('TOO_MANY_PHOTOS');
      if (selected.any((p) => p.bytes.length > 5242880) || [..._photos, ...selected].fold<int>(0, (n, p) => n + p.bytes.length) > 15728640) throw const DomesticTrackingException('FILE_TOO_LARGE');
      if (_valid) setState(() { _photos.addAll(selected); _message = null; });
    } catch (e) { if (_valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'REQUEST_FAILED')); }
    finally { if (mounted) setState(() => _picking = false); }
  }
  Future<void> _save() async {
    if (_busy || _finding || _picking || !_form.currentState!.validate()) return;
    if (_scope == 'statement' && _confirmed == null) { setState(() => _message = t('STATEMENT_REQUIRED')); return; }
    if (_scope == 'cargo' && _cargo == null) { setState(() => _message = t('CARGO_REQUIRED')); return; }
    setState(() => _busy = true);
    try {
      final data = await _call(widget.row == null ? 'save_batch' : 'save', {
        'id': widget.row?['id'], 'updated_at': widget.row?['updated_at'],
        'link_scope': _scope, 'statement': _scope == 'statement' ? _confirmed : null,
        'reference': _scope == 'reference' ? {'reference_type': _referenceType, 'reference_number': _reference.text} : null,
        'shipment_id': _scope == 'cargo' ? _cargo : null,
        'carrier': _carrier, 'tracking_number': _number.text,
        'delivery_kind': _kind, 'service_kind': _scope == 'reference' && _referenceType == 'ecommerce' ? 'ecommerce' : _service,
        'receiver_name': _name.text, 'receiver_phone': _phone.text,
        if (widget.row == null) 'waybills': [{'carrier': _carrier, 'tracking_number': _number.text}, ..._extraWaybills.map((w) => {'carrier': w.carrier, 'tracking_number': w.number.text})],
        'photos': _photos.map((p) => {'base64': base64Encode(p.bytes)}).toList(),
      });
      if (_valid) Navigator.pop(context, Map<String, dynamic>.from(widget.row == null ? (data['parcels'] as List).first : data['parcel']));
    } catch (e) { if (_valid) setState(() => _message = t(e is DomesticTrackingException ? e.code : 'REQUEST_FAILED')); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Widget _extraWaybill(_WaybillDraft draft) => Container(key: ObjectKey(draft),
    margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(border: Border.all(color: const Color(0xffd9e2ef)), borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      TextFormField(controller: draft.number, enabled: !_busy, maxLength: 40, decoration: InputDecoration(labelText: t('tracking')),
        validator: (v) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9\s-]{5,39}$').hasMatch(v?.trim() ?? '') ? null : t('INVALID_TRACKING'),
        onChanged: (v) => setState(() { if (!draft.chosen) draft.carrier = DomesticTrackingService.detectCarrier(v) ?? ''; })),
      DropdownButtonFormField<String>(key: ValueKey('extra-${identityHashCode(draft)}-${draft.carrier}'), initialValue: draft.carrier, isExpanded: true,
        decoration: InputDecoration(labelText: t('carrier')),
        items: [DropdownMenuItem(value: '', child: Text(t('selectCarrier'))), ...DomesticTrackingService.carriers.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))],
        validator: (v) => (v ?? '').isEmpty ? t('selectCarrier') : null,
        onChanged: _busy ? null : (v) => setState(() { draft.carrier = v!; draft.chosen = v.isNotEmpty; })),
      TextButton.icon(onPressed: _busy ? null : () { setState(() => _extraWaybills.remove(draft)); WidgetsBinding.instance.addPostFrameCallback((_) => draft.number.dispose()); }, icon: const Icon(Icons.remove_circle_outline), label: Text(t('removeWaybill'))),
    ]));

  Widget _choice(String label, String value, List<String> values, ValueChanged<String?> changed) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'), initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: t(label)),
      items: values.map((v) => DropdownMenuItem(value: v, child: Text(t(v)))).toList(),
      onChanged: _busy ? null : changed,
    ));
  Widget _statementSelector() {
    final routes = _batches.map((r) => r.route).toSet().toList()..sort();
    final years = _batches.where((r) => _route.isEmpty || r.route == _route).map((r) => '${r.year}').toSet().toList()..sort((a,b) => b.compareTo(a));
    final voyages = _batches.where((r) => (_route.isEmpty || r.route == _route) && (_year.isEmpty || '${r.year}' == _year)).map((r) => r.voyage).toSet().toList()
      ..sort((a,b) { final an = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? -1; final bn = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? -1; return an == bn ? a.compareTo(b) : bn.compareTo(an); });
    Widget select(String key, String value, List<String> values, ValueChanged<String> changed) => Padding(
      padding: const EdgeInsets.only(bottom: 12), child: DropdownButtonFormField<String>(
        key: ValueKey('link-$key-$value-${values.join(',')}'), initialValue: values.contains(value) ? value : '', isExpanded: true,
        decoration: InputDecoration(labelText: t(key)),
        items: [DropdownMenuItem(value: '', child: Text(t('any'))), ...values.map((v) => DropdownMenuItem(value: v, child: Text(key == 'route' ? RouteCatalog.localizedLabel(v, widget.language) : v)))],
        onChanged: _busy || _filtersLoading || values.isEmpty ? null : (v) => setState(() { changed(v ?? ''); _invalidate(); }),
      ));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('mappingHelp')), const SizedBox(height: 12),
      if (_filtersLoading) Text(t('filtersLoading')),
      if (_filtersFailed) ...[Text(t('filtersFailed')), TextButton(onPressed: _busy ? null : _loadBatches, child: Text(t('retry')))],
      if (!_filtersLoading && !_filtersFailed && _batches.isEmpty) Text(t('filtersEmpty')),
      select('route', _route, routes, (v) { _route = v; _year = ''; _voyage = ''; }),
      select('year', _year, years, (v) { _year = v; _voyage = ''; }),
      select('voyage', _voyage, voyages, (v) => _voyage = v),
      TextFormField(key: const Key('delivery-receipt-number'), controller: _receipt, enabled: !_busy, maxLength: 80,
        decoration: InputDecoration(labelText: t('statementNumber'), hintText: t('exampleStatement')),
        onChanged: (_) => setState(_invalidate), onFieldSubmitted: (_) => _confirmStatement()),
      OutlinedButton(key: const Key('delivery-confirm-statement'), onPressed: _busy || _finding || _filtersLoading ? null : _confirmStatement, child: Text(t('confirmStatement'))),
      if (_confirmed != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${t('statementConfirmed')}\n${_confirmed!['route']} · ${_confirmed!['shipment_year']} / ${_confirmed!['voyage']} · ${_confirmed!['receipt_number']}${_cargoCount == null ? '' : '\n${t('cargoCount')} $_cargoCount'}')),
    ]);
  }
  Widget _cargoSelector() => Column(children: [
    TextField(controller: _cargoQuery, enabled: !_busy, decoration: InputDecoration(labelText: t('cargoSearch')), onSubmitted: (_) => _findCargo()),
    TextButton(onPressed: _finding || _busy ? null : _findCargo, child: Text(t('search'))),
    DropdownButtonFormField<int>(key: ValueKey('cargo-$_cargo-${_cargoRows.length}'), initialValue: _cargo ?? 0, isExpanded: true,
      decoration: InputDecoration(labelText: t('linkCargo')),
      items: [DropdownMenuItem(value: 0, child: Text(t('linkCargo'))), ..._cargoRows.map((r) => DropdownMenuItem(value: (r['id'] as num).toInt(), child: Text('${r['box_number']} · ${r['receipt_number'] ?? r['invoice_number'] ?? ''}', overflow: TextOverflow.ellipsis)))],
      onChanged: _busy ? null : (v) => setState(() {
        _cargo = v == 0 ? null : v; final rows = _cargoRows.where((r) => r['id'] == _cargo);
        _name.text = rows.isEmpty ? '' : '${rows.first['consignee_name'] ?? ''}'; _phone.text = rows.isEmpty ? '' : '${rows.first['consignee_phone'] ?? ''}';
      })),
  ]);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t(widget.row == null ? 'add' : 'edit'))),
    body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
      Text(t('stepStatement'), style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12),
      DropdownButtonFormField<String>(key: ValueKey('scope-$_scope'), initialValue: _scope, isExpanded: true,
        decoration: InputDecoration(labelText: t('linkMethod')),
        items: [for (final pair in [['statement','linkStatement'],['reference','linkReference'],['cargo','linkCargo'],if (_scope == 'standalone') ['standalone','linkLegacy']]) DropdownMenuItem(value: pair[0], child: Text(t(pair[1])))],
        onChanged: _busy ? null : (v) => setState(() { _scope = v!; _lookupVersion++; _message = null; })),
      const SizedBox(height: 12),
      if (_scope == 'statement') _statementSelector(),
      if (_scope == 'reference') ...[
        Text(t('referenceHelp')), const SizedBox(height: 12),
        _choice('referenceType', _referenceType, ['ecommerce','local'], (v) => setState(() { _referenceType = v!; if (v == 'ecommerce') _service = 'ecommerce'; })),
        TextFormField(key: const Key('delivery-reference-number'), controller: _reference, enabled: !_busy, maxLength: 80, decoration: InputDecoration(labelText: t('referenceNumber')),
          validator: (v) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ./_-]{0,79}$').hasMatch(v?.trim() ?? '') ? null : t('INVALID_REFERENCE')),
      ],
      if (_scope == 'cargo') _cargoSelector(),
      const SizedBox(height: 20), Text(t('stepWaybill'), style: Theme.of(context).textTheme.titleMedium), Text(t('waybillHelp')), const SizedBox(height: 12),
      TextFormField(key: const Key('delivery-tracking-number'), controller: _number, enabled: !_busy, maxLength: 40, decoration: InputDecoration(labelText: t('tracking')),
        onChanged: (v) => setState(() { if (!_carrierChosen) _carrier = DomesticTrackingService.detectCarrier(v) ?? ''; }),
        validator: (v) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9\s-]{5,39}$').hasMatch(v?.trim() ?? '') ? null : t('INVALID_TRACKING')),
      DropdownButtonFormField<String>(key: ValueKey('carrier-$_carrier'), initialValue: _carrier, isExpanded: true, decoration: InputDecoration(labelText: t('carrier')),
        items: [DropdownMenuItem(value: '', child: Text(t('selectCarrier'))), ...DomesticTrackingService.carriers.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))],
        validator: (v) => (v ?? '').isEmpty ? t('selectCarrier') : null,
        onChanged: _busy ? null : (v) => setState(() { _carrier = v!; _carrierChosen = v.isNotEmpty; })),
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t('carrierHint'))),
      ..._extraWaybills.map(_extraWaybill),
      if (widget.row == null) OutlinedButton.icon(key: const Key('delivery-add-waybill'), onPressed: _busy || _extraWaybills.length >= 19 ? null : () => setState(() => _extraWaybills.add(_WaybillDraft())), icon: const Icon(Icons.add), label: Text(t('addWaybill'))),
      if (widget.row != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(t('correctionHelp'))),
      _choice('kind', _kind, ['city','province'], (v) => setState(() => _kind = v!)),
      _choice('service', _service, ['domestic','inbound','outbound','ecommerce','express'], (v) => setState(() => _service = v!)),
      TextField(controller: _name, enabled: !_busy, readOnly: ['statement','cargo'].contains(_scope), maxLength: 160, decoration: InputDecoration(labelText: t('receiver'))),
      TextField(controller: _phone, enabled: !_busy, readOnly: ['statement','cargo'].contains(_scope), maxLength: 40, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('phone'))),
      Text(t('photoHelp')),
      OutlinedButton.icon(key: const Key('delivery-pick-photos'), onPressed: _busy || _picking ? null : _pick, icon: const Icon(Icons.image_outlined), label: Text(t('photoInput'))),
      for (final photo in _photos) ListTile(title: Text(photo.name), leading: Image.memory(photo.bytes, width: 48, height: 48, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined)), trailing: IconButton(tooltip: t('removePhoto'), icon: const Icon(Icons.close), onPressed: _busy ? null : () => setState(() => _photos.remove(photo)))),
      if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_message!)),
      if (_busy || _finding) const LinearProgressIndicator(),
      FilledButton(key: const Key('delivery-save'), onPressed: _busy || _finding || _picking ? null : _save, child: Text(t('save'))),
    ])),
  );
}

class DomesticEventEditor extends StatefulWidget {
  const DomesticEventEditor({
    super.key,
    required this.language,
    required this.row,
  });
  final AppLanguage language;
  final Map<String, dynamic> row;
  @override
  State<DomesticEventEditor> createState() => _DomesticEventEditorState();
}

class _DomesticEventEditorState extends State<DomesticEventEditor> with SharedUiTextState {
  final _where = TextEditingController(),
      _description = TextEditingController();
  late final TextEditingController _when;
  String _status = 'accepted';
  String? _message;
  bool _busy = false;
  String t(String k) => domesticText(widget.language, k);
  @override
  void initState() {
    super.initState();
    _when = TextEditingController(
      text: DomesticTrackingService.laoDate(
        DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  @override
  void dispose() {
    _where.dispose();
    _description.dispose();
    _when.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final time = DateTime.tryParse(
      '${_when.text.trim().replaceAll(' ', 'T')}:00+07:00',
    );
    if (time == null || _description.text.trim().isEmpty) {
      setState(() => _message = t('REQUEST_FAILED'));
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await DomesticTrackingService.call('add_event', {
        'id': widget.row['id'],
        'updated_at': widget.row['updated_at'],
        'occurred_at': time.toUtc().toIso8601String(),
        'location': _where.text,
        'description': _description.text,
        'status': _status,
      });
      if (mounted)
        Navigator.pop(context, Map<String, dynamic>.from(data['parcel']));
    } catch (e) {
      if (mounted)
        setState(
          () => _message = t(
            e is DomesticTrackingException ? e.code : 'REQUEST_FAILED',
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('manual'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _when,
          decoration: InputDecoration(
            labelText: t('when'),
            helperText: 'YYYY-MM-DD HH:mm',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _status,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('status')),
          items: DomesticTrackingService.statuses
              .map((s) => DropdownMenuItem(value: s, child: Text(t(s))))
              .toList(),
          onChanged: _busy ? null : (v) => setState(() => _status = v!),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _where,
          maxLength: 240,
          decoration: InputDecoration(labelText: t('location')),
        ),
        TextField(
          controller: _description,
          maxLength: 1200,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(labelText: t('description')),
        ),
        if (_message != null) Text(_message!),
        if (_busy) const LinearProgressIndicator(),
        FilledButton(onPressed: _busy ? null : _save, child: Text(t('save'))),
      ],
    ),
  );
}


