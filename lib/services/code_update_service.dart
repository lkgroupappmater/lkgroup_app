import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

enum CodeUpdateStatus {
  checking,
  unsupported,
  current,
  available,
  downloading,
  ready,
  error,
}

enum CodeUpdateNotice { ready, applied, unsupported }

/// Device-local OTA state. Account notifications and Play installs stay separate.
/// Checks/downloads never block startup or restart the app while work is open.
class CodeUpdateService extends ChangeNotifier {
  CodeUpdateService({
    ShorebirdUpdater? updater,
    Future<SharedPreferences> Function()? preferences,
    Future<String> Function()? versionLoader,
    DateTime Function()? clock,
  }) : _updater = updater ?? ShorebirdUpdater(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _versionLoader = versionLoader ?? _installedVersion,
       _clock = clock ?? DateTime.now;

  static final instance = CodeUpdateService();
  static const _seenKey = 'lk.code_update.seen_notices';
  static const _installedKey = 'lk.code_update.installed';
  final ShorebirdUpdater _updater;
  final Future<SharedPreferences> Function() _preferences;
  final Future<String> Function() _versionLoader;
  final DateTime Function() _clock;
  SharedPreferences? _prefs;
  final Set<String> _seen = {};
  bool _loaded = false;
  bool _busy = false;
  bool _disposed = false;
  String version = '-';
  int? currentPatch;
  int? nextPatch;
  DateTime? lastChecked;
  CodeUpdateStatus status = CodeUpdateStatus.checking;
  CodeUpdateNotice? notice;
  String? noticeId;

  bool get busy => _busy;
  bool get hasUnread => noticeId != null && !_seen.contains(noticeId);
  bool get needsPopup => hasUnread;

  static Future<String> _installedVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      _prefs = await _preferences();
      _seen.addAll(_prefs!.getStringList(_seenKey) ?? const <String>[]);
    } catch (_) {
      /* Missing local storage must not disable the updater. */
    }
    try {
      version = await _versionLoader();
    } catch (_) {
      /* Show unknown, never guess. */
    }
    _loaded = true;
  }

  void _setNotice(CodeUpdateNotice kind, String id) {
    notice = kind;
    noticeId = id;
  }

  Future<void> _readPatches() async {
    final current = (await _updater.readCurrentPatch())?.number;
    final next = (await _updater.readNextPatch())?.number;
    currentPatch = current;
    nextPatch = next;
    notice = null;
    noticeId = null;
    final installed = '$version:patch:${currentPatch ?? 0}';
    final previous = _prefs?.getString(_installedKey);
    // A fresh base install is not falsely reported as a downloaded OTA patch.
    if (currentPatch != null || (previous != null && previous != installed)) {
      _setNotice(CodeUpdateNotice.applied, installed);
    }
    try {
      await _prefs?.setString(_installedKey, installed);
    } catch (_) {}
  }

  void _ready() {
    status = CodeUpdateStatus.ready;
    _setNotice(CodeUpdateNotice.ready, '$version:patch:${nextPatch ?? 0}');
  }

  Future<void> check({bool force = false}) async {
    if (_busy || _disposed) return;
    final interval = status == CodeUpdateStatus.error
        ? const Duration(minutes: 1)
        : const Duration(minutes: 30);
    if (!force &&
        lastChecked != null &&
        _clock().difference(lastChecked!) < interval)
      return;
    _busy = true;
    status = CodeUpdateStatus.checking;
    _emit();
    try {
      await _load();
      if (!_updater.isAvailable) {
        status = CodeUpdateStatus.unsupported;
        _setNotice(CodeUpdateNotice.unsupported, '$version:unsupported');
        return;
      }
      await _readPatches();
      // Includes an engine background download and rollback to a lower/base patch.
      if (nextPatch != currentPatch) {
        _ready();
        return;
      }
      final result = await _updater.checkForUpdate(track: UpdateTrack.stable);
      switch (result) {
        case UpdateStatus.unavailable:
          status = CodeUpdateStatus.unsupported;
          _setNotice(CodeUpdateNotice.unsupported, '$version:unsupported');
        case UpdateStatus.upToDate:
          status = CodeUpdateStatus.current;
        case UpdateStatus.restartRequired:
          nextPatch = (await _updater.readNextPatch())?.number;
          _ready();
        case UpdateStatus.outdated:
          status = CodeUpdateStatus.available;
          _emit();
          status = CodeUpdateStatus.downloading;
          _emit();
          await _updater.update(track: UpdateTrack.stable);
          nextPatch = (await _updater.readNextPatch())?.number;
          if (nextPatch != currentPatch) {
            _ready();
          } else {
            // A competing engine download may have won; ask for its real state.
            final after = await _updater.checkForUpdate(
              track: UpdateTrack.stable,
            );
            if (after == UpdateStatus.restartRequired) {
              _ready();
            } else if (after == UpdateStatus.upToDate) {
              status = CodeUpdateStatus.current;
            } else {
              status = CodeUpdateStatus.error;
            }
          }
      }
    } catch (_) {
      // Preserve a verified pending patch if only the network check failed.
      if (nextPatch != currentPatch) {
        _ready();
      } else {
        status = CodeUpdateStatus.error;
      }
    } finally {
      lastChecked = _clock();
      _busy = false;
      _emit();
    }
  }

  Future<void> acknowledge([String? id]) async {
    final key = id ?? noticeId;
    if (key == null) return;
    _seen.add(key);
    _emit();
    try {
      final entries = _seen.toList();
      await _prefs?.setStringList(
        _seenKey,
        entries.length > 40 ? entries.sublist(entries.length - 40) : entries,
      );
    } catch (_) {
      /* The in-memory acknowledgement still prevents repeated popups. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
