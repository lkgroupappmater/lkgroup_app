import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppUpdateStatus { unavailable, available, downloading, ready }

/// Google Play owns download verification and installation. Direct APK installs
/// are not eligible; Shorebird patches use the engine's separate update path.
class AppUpdateService extends ValueNotifier<AppUpdateStatus> {
  AppUpdateService._() : super(AppUpdateStatus.unavailable) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') _apply(call.arguments);
    });
  }
  static final instance = AppUpdateService._();
  static const _channel = MethodChannel('com.lkgrouptrading.app/updates');
  bool _checking = false;
  bool _acting = false;
  DateTime? _lastCheck;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _apply(dynamic result) {
    value = switch (result) {
      'available' => AppUpdateStatus.available,
      'downloading' => AppUpdateStatus.downloading,
      'ready' => AppUpdateStatus.ready,
      _ => AppUpdateStatus.unavailable,
    };
  }

  Future<void> check({bool force = false}) async {
    if (!_supported || _checking) return;
    if (!force && _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(minutes: 30)) return;
    _checking = true;
    try {
      _apply(await _channel.invokeMethod<String>('check'));
      _lastCheck = DateTime.now();
    } on PlatformException {
      // Offline / not installed through Play: leave the app usable.
    } on MissingPluginException {
      // Tests, desktop and binaries built before this native bridge.
    } finally {
      _checking = false;
    }
  }

  Future<bool> download() => _act('download');
  Future<bool> install() => _act('install');

  Future<bool> _act(String method) async {
    if (!_supported || _acting) return false;
    _acting = true;
    try {
      final result = await _channel.invokeMethod<String>(method);
      // A fast download can finish before the consent activity returns.
      if (result != null && !(result == 'downloading' && value == AppUpdateStatus.ready)) {
        _apply(result);
      }
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } finally {
      _acting = false;
    }
  }
}
