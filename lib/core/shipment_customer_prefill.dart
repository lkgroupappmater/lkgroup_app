import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Only untouched fields receive suggestions; stale customer/voyage responses are discarded.
class ShipmentCustomerPrefill extends ChangeNotifier {
  ShipmentCustomerPrefill({required this.name, required this.phone, required this.zone, required this.notes,
    required this.scope, required this.lookup}) {
    name.addListener(refresh); phone.addListener(refresh);
    zone.addListener(_zoneChanged); notes.addListener(_notesChanged);
    _dirtyZone = zone.text.isNotEmpty; _dirtyNotes = notes.text.isNotEmpty;
  }
  final TextEditingController name, phone, zone, notes;
  final String Function() scope;
  final Future<Map<String, dynamic>> Function(String name, String phone) lookup;
  Timer? _timer;
  int _revision = 0;
  bool _disposed = false, _applying = false, _dirtyZone = false, _dirtyNotes = false;
  String status = '';
  void _zoneChanged() { if (!_applying) _dirtyZone = true; }
  void _notesChanged() { if (!_applying) _dirtyNotes = true; }
  void refresh() {
    _timer?.cancel(); _revision++;
    _applying = true;
    if (!_dirtyZone) zone.clear(); if (!_dirtyNotes) notes.clear();
    _applying = false; status = ''; notifyListeners();
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty || scope().isEmpty) return;
    _timer = Timer(const Duration(milliseconds: 350), runNow);
  }
  Future<void> runNow() async {
    _timer?.cancel(); final revision = ++_revision, batch = scope();
    if (_disposed || name.text.trim().isEmpty || phone.text.trim().isEmpty || batch.isEmpty) return;
    try {
      final result = await lookup(name.text.trim(), phone.text.trim());
      if (_disposed || revision != _revision || batch != scope()) return;
      status = '${result['status'] ?? ''}';
      if (status == 'matched' && result['values'] is Map) {
        final values = result['values'] as Map; _applying = true;
        if (!_dirtyZone) zone.text = '${values['unloading_zone'] ?? ''}';
        if (!_dirtyNotes) notes.text = '${values['notes'] ?? ''}';
        _applying = false;
      }
    } catch (_) { if (!_disposed && revision == _revision) status = 'error'; }
    if (!_disposed) notifyListeners();
  }
  @override
  void dispose() {
    _disposed = true; _revision++; _timer?.cancel();
    name.removeListener(refresh); phone.removeListener(refresh);
    zone.removeListener(_zoneChanged); notes.removeListener(_notesChanged); super.dispose();
  }
}
