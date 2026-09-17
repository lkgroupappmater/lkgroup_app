import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../core/shared_ui_text_catalog.dart';
import 'live_data_service.dart';

typedef SharedTextPageLoader = Future<List<Map<String, dynamic>>> Function(int offset, int limit);

/// Public fixed copy only. Never pass customer or workbook values here.
class SharedUiTextService extends ChangeNotifier {
  SharedUiTextService({SharedTextPageLoader? loadPage}) : _loadPage = loadPage;
  static final instance = SharedUiTextService();
  final SharedTextPageLoader? _loadPage;
  Map<String, Map<String, dynamic>> _rows = {};
  Future<bool>? _pending;
  bool _started = false;
  bool _disposed = false;

  static String canonicalKey(String key) => sharedTextAliases[key] ?? key;

  String text(String key, String language, String fallback) {
    key = canonicalKey(key);
    final base = sharedTextDefaults[key];
    final value = _rows[key]?[language];
    if (value is String && value.isNotEmpty) return value;
    return base?[language]?.isNotEmpty == true ? base![language]! : fallback;
  }

  String korean(String source, String language, String fallback) {
    final key = sharedKoreanTextKeys[source];
    return key == null ? fallback : text(key, language, fallback);
  }

  void start() {
    if (_started || !SupabaseConfig.isConfigured) return;
    _started = true;
    LiveDataService.instance.addListener(_onLiveData);
    unawaited(refresh());
  }

  void _onLiveData() {
    if (LiveDataService.instance.foreground) unawaited(refresh());
  }

  Future<bool> refresh() {
    if (_disposed) return Future.value(false);
    return _pending ??= _refresh().whenComplete(() => _pending = null);
  }

  Future<bool> _refresh() async {
    if (_loadPage == null && !SupabaseConfig.isConfigured) return false;
    try {
      final rows = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 500) {
        final page = _loadPage != null
            ? await _loadPage(offset, 500)
            : await Supabase.instance.client.from('site_public_text')
                .select('key,ko,en,lo,updated_at').order('key')
                .range(offset, offset + 499).timeout(const Duration(seconds: 10));
        rows.addAll(page);
        if (page.length < 500) break;
      }
      if (_disposed) return false;
      applyRows(rows);
      return true;
    } catch (_) {
      // Retain the last complete snapshot on failed/offline reads.
      return false;
    }
  }

  @visibleForTesting
  void applyRows(List<Map<String, dynamic>> rows) {
    final next = <String, Map<String, dynamic>>{};
    final sorted = [...rows]..sort((a, b) {
      final order = '${a['updated_at'] ?? ''}'.compareTo('${b['updated_at'] ?? ''}');
      if (order != 0) return order;
      return (canonicalKey('${a['key']}') == a['key'] ? 1 : 0)
          .compareTo(canonicalKey('${b['key']}') == b['key'] ? 1 : 0);
    });
    for (final row in sorted) {
      final key = canonicalKey('${row['key'] ?? ''}');
      final base = sharedTextDefaults[key];
      if (base == null) continue;
      final values = <String, dynamic>{};
      for (final lang in ['ko', 'en', 'lo']) {
        final value = row[lang];
        if (value is String && value.length <= 12000 &&
            (value.isEmpty || setEquals(_variables(value), _variables(base[lang] ?? base['ko'] ?? '')))) {
          values[lang] = value;
        }
      }
      next[key] = values;
    }
    if (jsonEncode(next) == jsonEncode(_rows)) return;
    _rows = next;
    notifyListeners();
  }

  Set<String> _variables(String value) => RegExp(r'\{([a-zA-Z][\w]*)\}')
      .allMatches(value).map((match) => match.group(1)!).toSet();

  @override
  void dispose() {
    _disposed = true;
    if (_started) LiveDataService.instance.removeListener(_onLiveData);
    super.dispose();
  }
}

/// Rebuild labels in place; State objects and input controllers are retained.
mixin SharedUiTextState<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    SharedUiTextService.instance.addListener(_onSharedText);
  }

  void _onSharedText() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SharedUiTextService.instance.removeListener(_onSharedText);
    super.dispose();
  }
}
