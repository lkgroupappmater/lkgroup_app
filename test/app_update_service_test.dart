import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/services/app_update_service.dart';
import 'package:lkgroup_app/widgets/app_update_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.lkgrouptrading.app/updates');
  final calls = <String>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    AppUpdateService.instance.value = AppUpdateStatus.unavailable;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'download' ? 'downloading' : 'available';
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('availability check never starts installation and is rate limited', () async {
    await AppUpdateService.instance.check(force: true);
    await AppUpdateService.instance.check();
    expect(calls, ['check']);
    expect(AppUpdateService.instance.value, AppUpdateStatus.available);
    expect(await AppUpdateService.instance.download(), isTrue);
    expect(AppUpdateService.instance.value, AppUpdateStatus.downloading);
    expect(calls, ['check', 'download']);
  });

  test('offline and unsupported platforms leave the app usable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'play_update_unavailable');
    });
    await AppUpdateService.instance.check(force: true);
    expect(AppUpdateService.instance.value, AppUpdateStatus.unavailable);
    expect(await AppUpdateService.instance.download(), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await AppUpdateService.instance.install(), isFalse);
  });

  testWidgets('a ready update does not restart without explicit confirmation', (tester) async {
    AppUpdateService.instance.value = AppUpdateStatus.ready;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: AppUpdateBanner(language: AppLanguage.korean))));
    expect(calls, isEmpty);
    await tester.tap(find.text('다시 시작'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });
}
