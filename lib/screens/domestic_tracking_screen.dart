import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';
import '../core/domestic_tracking_text.dart';
import '../models/app_user.dart';
import '../services/domestic_tracking_service.dart';

class DomesticTrackingScreen extends StatefulWidget {
  const DomesticTrackingScreen({
    super.key,
    required this.language,
    this.user,
    this.manage = false,
  });
  final AppLanguage language;
  final AppUser? user;
  final bool manage;
  @override
  State<DomesticTrackingScreen> createState() => _DomesticTrackingScreenState();
}

class _DomesticTrackingScreenState extends State<DomesticTrackingScreen> {
  final _number = TextEditingController();
  String _carrier = '';
  bool _busy = false, _more = false;
  int _page = 0;
  String? _message;
  List<Map<String, dynamic>> _rows = [];
  String t(String k) => domesticText(widget.language, k);
  bool get manager =>
      [UserRole.admin, UserRole.staff].contains(widget.user?.role);
  bool get isOperator => manager || widget.user?.role == UserRole.partner;
  String error(Object e) =>
      t(e is DomesticTrackingException ? e.code : 'REQUEST_FAILED');
  @override
  void initState() {
    super.initState();
    if (widget.manage && isOperator) _list();
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _run(String action, Map<String, dynamic> args) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = t('loading');
      _rows = [];
      _more = false;
      if (action == 'lookup') _page = 0;
    });
    try {
      final data = await DomesticTrackingService.call(action, args);
      if (!mounted) return;
      setState(() {
        _rows = (data['parcels'] as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
        _more = data['has_more'] == true;
        _message = _rows.isEmpty ? t('empty') : null;
      });
    } catch (e) {
      if (mounted) setState(() => _message = error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _list() => _run('list', {'page': _page});
  Future<void> _lookup([Map<String, dynamic>? r]) => _run('lookup', {
    'carrier': r?['carrier'] ?? _carrier,
    'tracking_number': r?['tracking_number'] ?? _number.text,
  });
  Future<void> _edit([Map<String, dynamic>? row]) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            DomesticWaybillEditor(language: widget.language, row: row),
      ),
    );
    if (result != null && mounted) await _lookup(result);
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
              Text(t('hint')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
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
                maxLength: 40,
                decoration: InputDecoration(labelText: t('tracking')),
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
                    if (manager)
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
              ..._rows.map(_card),
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
                                _list();
                              },
                        child: Text(t('prev')),
                      ),
                    if (_more)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _page++;
                                _list();
                              },
                        child: Text(t('more')),
                      ),
                  ],
                ),
            ],
          ),
  );
  Widget _card(Map<String, dynamic> r) {
    final photo = r['photo_url'] as String?;
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
                '${cargo['box_number']} · ${cargo['route']} · ${cargo['shipment_year']} / ${cargo['voyage']}',
              ),
            const SizedBox(height: 12),
            Text(t('photo'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (photo != null)
              InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: Stack(
                      children: [
                        InteractiveViewer(
                          child: Image.network(
                            photo,
                            errorBuilder: (_, __, ___) => Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(t('REQUEST_FAILED')),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: Image.network(
                  photo,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(t('REQUEST_FAILED')),
                ),
              )
            else
              Text(t(r['photo_restricted'] == true ? 'restricted' : 'noPhoto')),
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
                      child: Icon(
                        Icons.radio_button_checked,
                        size: 16,
                        color: Color(0xff315b9c),
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

class DomesticWaybillEditor extends StatefulWidget {
  const DomesticWaybillEditor({super.key, required this.language, this.row});
  final AppLanguage language;
  final Map<String, dynamic>? row;
  @override
  State<DomesticWaybillEditor> createState() => _DomesticWaybillEditorState();
}

class _DomesticWaybillEditorState extends State<DomesticWaybillEditor> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController(),
      _name = TextEditingController(),
      _phone = TextEditingController(),
      _cargoQuery = TextEditingController();
  String _carrier = 'HAL', _kind = 'province', _service = 'domestic';
  int? _cargo;
  List<Map<String, dynamic>> _cargoRows = [];
  Uint8List? _photo;
  String? _photoName, _message;
  bool _busy = false, _finding = false;
  String t(String k) => domesticText(widget.language, k);
  @override
  void initState() {
    super.initState();
    final r = widget.row;
    if (r != null) {
      _carrier = r['carrier'];
      _kind = r['delivery_kind'];
      _service = r['service_kind'];
      _number.text = r['tracking_number'];
      _name.text = r['receiver_name'] ?? '';
      _phone.text = r['receiver_phone'] ?? '';
      _cargo = r['shipment_id'];
      if (r['cargo'] is Map)
        _cargoRows = [Map<String, dynamic>.from(r['cargo'])];
    }
  }

  @override
  void dispose() {
    for (final c in [_number, _name, _phone, _cargoQuery]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5242880)
        throw const DomesticTrackingException('FILE_TOO_LARGE');
      if (mounted)
        setState(() {
          _photo = bytes;
          _photoName = file.name;
        });
    } catch (e) {
      if (mounted)
        setState(
          () => _message = t(
            e is DomesticTrackingException ? e.code : 'REQUEST_FAILED',
          ),
        );
    }
  }

  Future<void> _findCargo() async {
    if (_finding) return;
    setState(() => _finding = true);
    try {
      final data = await DomesticTrackingService.call('cargo_search', {
        'query': _cargoQuery.text,
      });
      if (mounted)
        setState(() {
          final old = _cargoRows.where((r) => r['id'] == _cargo).toList();
          _cargoRows = [
            ...old,
            ...(data['cargo'] as List)
                .map((r) => Map<String, dynamic>.from(r))
                .where((r) => r['id'] != _cargo),
          ];
          _message = _cargoRows.isEmpty ? t('empty') : null;
        });
    } catch (e) {
      if (mounted)
        setState(
          () => _message = t(
            e is DomesticTrackingException ? e.code : 'REQUEST_FAILED',
          ),
        );
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final data = await DomesticTrackingService.call('save', {
        'id': widget.row?['id'],
        'updated_at': widget.row?['updated_at'],
        'carrier': _carrier,
        'tracking_number': _number.text,
        'delivery_kind': _kind,
        'service_kind': _service,
        'shipment_id': _cargo,
        'receiver_name': _name.text,
        'receiver_phone': _phone.text,
        if (_photo != null) 'photo': {'base64': base64Encode(_photo!)},
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

  Widget _choice(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: t(label)),
      items: values
          .map((v) => DropdownMenuItem(value: v, child: Text(t(v))))
          .toList(),
      onChanged: _busy ? null : changed,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t(widget.row == null ? 'add' : 'edit'))),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _carrier,
            isExpanded: true,
            decoration: InputDecoration(labelText: t('carrier')),
            items: DomesticTrackingService.carriers.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: _busy || widget.row != null
                ? null
                : (v) => setState(() => _carrier = v!),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _number,
            readOnly: widget.row != null,
            maxLength: 40,
            decoration: InputDecoration(labelText: t('tracking')),
            validator: (v) =>
                RegExp(r'^[A-Za-z0-9][A-Za-z0-9\s-]{5,39}$')
                    .hasMatch(v?.trim() ?? '')
                ? null
                : t('INVALID_TRACKING'),
          ),
          _choice('kind', _kind, [
            'city',
            'province',
          ], (v) => setState(() => _kind = v!)),
          _choice('service', _service, [
            'domestic',
            'inbound',
            'outbound',
            'ecommerce',
            'express',
          ], (v) => setState(() => _service = v!)),
          Text(t('cargo')),
          TextField(
            controller: _cargoQuery,
            decoration: InputDecoration(labelText: t('cargoSearch')),
            onSubmitted: (_) => _findCargo(),
          ),
          TextButton.icon(
            onPressed: _finding || _busy ? null : _findCargo,
            icon: const Icon(Icons.search),
            label: Text(t('search')),
          ),
          DropdownButtonFormField<int>(
            key: ValueKey('cargo-$_cargo-${_cargoRows.length}'),
            initialValue: _cargo ?? 0,
            isExpanded: true,
            items: [
              DropdownMenuItem(value: 0, child: Text(t('unlinked'))),
              ..._cargoRows.map(
                (r) => DropdownMenuItem(
                  value: r['id'] as int,
                  child: Text(
                    '${r['box_number']} · ${r['shipment_year']} / ${r['voyage']} · ${r['consignee_name'] ?? r['route']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _cargo = v == 0 ? null : v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            maxLength: 160,
            decoration: InputDecoration(labelText: t('receiver')),
          ),
          TextField(
            controller: _phone,
            maxLength: 40,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: t('phone')),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(t('photoInput')),
          ),
          if (_photo != null) ...[
            Text(_photoName ?? ''),
            Image.memory(_photo!, height: 150, fit: BoxFit.contain),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_message!),
            ),
          if (_busy) const LinearProgressIndicator(),
          FilledButton(onPressed: _busy ? null : _save, child: Text(t('save'))),
        ],
      ),
    ),
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

class _DomesticEventEditorState extends State<DomesticEventEditor> {
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
          decoration: InputDecoration(
            labelText: AppStrings.get(widget.language, 'status'),
          ),
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
