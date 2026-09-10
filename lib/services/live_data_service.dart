import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Carries invalidation signals only. Screens still use their existing,
/// authenticated queries/RPCs; no shipment data is sent on this channel.
class LiveDataService extends ChangeNotifier with WidgetsBindingObserver {
  LiveDataService._();
  static final instance = LiveDataService._();

  bool _started = false;
  bool foreground = true;
  Set<String> topics = const {'*'};
  final Set<String> _pending = {};
  RealtimeChannel? _channel;
  Timer? _poll;
  Timer? _debounce;
  int _generation = 0;

  void start() {
    if (_started || !SupabaseConfig.isConfigured) return;
    _started = true;
    foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    // App-lifetime subscription; Supabase manages token refresh itself.
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut) {
        _connect();
        _queue('*');
      }
    });
    _connect();
    _startPoll();
  }

  void _startPoll() {
    _poll?.cancel();
    if (!foreground) return;
    // Also catches missed events, reconnects and changes made via RPCs.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _queue('*'));
  }

  void _connect() {
    final client = Supabase.instance.client;
    final previous = _channel;
    _channel = null;
    if (previous != null) {
      unawaited(client.removeChannel(previous).then<void>((_) {}, onError: (Object _) {}));
    }
    if (!foreground) return;
    final generation = ++_generation;
    _channel = client.channel('app-data-revisions-$generation')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'app_data_revisions',
        callback: (payload) {
          if (generation == _generation) {
            _queue('${payload.newRecord['topic'] ?? '*'}');
          }
        },
      )
      ..subscribe((status, error) {
        if (generation == _generation && status == RealtimeSubscribeStatus.subscribed) {
          _queue('*');
        }
      });
  }

  void _queue(String topic) {
    if (!foreground) return;
    _pending.add(topic);
    // Batch events from Excel imports without delaying forever under load.
    _debounce ??= Timer(const Duration(seconds: 1), () {
      _debounce = null;
      if (!foreground) return;
      topics = Set.unmodifiable(_pending);
      _pending.clear();
      notifyListeners();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _poll?.cancel();
    _debounce?.cancel();
    _debounce = null;
    _pending.clear();
    _connect();
    if (foreground) {
      _startPoll();
      _queue('*');
    }
  }
}
