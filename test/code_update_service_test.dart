import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import '../lib/services/code_update_service.dart';

class FakeUpdater implements ShorebirdUpdater {
  bool available = true;
  int? current;
  int? next;
  UpdateStatus result = UpdateStatus.upToDate;
  bool failCheck = false;
  bool failDownload = false;
  bool failReadNext = false;
  int checks = 0;
  int downloads = 0;
  Completer<void>? downloadGate;
  @override
  bool get isAvailable => available;
  @override
  Future<Patch?> readCurrentPatch() async =>
      current == null ? null : Patch(number: current!);
  @override
  Future<Patch?> readNextPatch() async {
    if (failReadNext) throw Exception('local read failure');
    return next == null ? null : Patch(number: next!);
  }

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    expect(track, UpdateTrack.stable);
    checks++;
    if (failCheck) throw Exception('offline');
    return result;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    expect(track, UpdateTrack.stable);
    downloads++;
    if (failDownload) throw Exception('download failed');
    await downloadGate?.future;
    next = (current ?? 0) + 1;
    result = UpdateStatus.restartRequired;
  }
}

CodeUpdateService serviceFor(
  FakeUpdater updater, {
  String version = '1.0.3+4',
}) => CodeUpdateService(
  updater: updater,
  versionLoader: () async => version,
  runtime: CodeUpdateRuntime.release,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final runtime in [
    CodeUpdateRuntime.debug,
    CodeUpdateRuntime.profile,
    CodeUpdateRuntime.web,
  ]) {
    test(
      '$runtime explains expected limitation without an update popup',
      () async {
        final api = FakeUpdater()..available = false;
        final service = CodeUpdateService(
          updater: api,
          versionLoader: () async => '1.0.4+5',
          runtime: runtime,
        );
        await service.check();
        expect(service.status, CodeUpdateStatus.development);
        expect(service.needsPopup, isFalse);
        expect(service.hasUnread, isFalse);
        expect(api.checks, 0);
        expect(api.downloads, 0);
        service.dispose();
      },
    );
  }

  test(
    'an engine background download is announced without downloading twice',
    () async {
      final api = FakeUpdater()
        ..current = 1
        ..next = 2;
      final s = serviceFor(api);
      await s.check();
      expect(s.status, CodeUpdateStatus.ready);
      expect(s.currentPatch, 1);
      expect(s.nextPatch, 2);
      expect(s.needsPopup, isTrue);
      expect(api.downloads, 0);
      expect(api.checks, 0);
      s.dispose();
    },
  );

  test(
    'same patch popup stays acknowledged across restarts and application',
    () async {
      final api = FakeUpdater()..next = 2;
      final s = serviceFor(api);
      await s.check();
      await s.acknowledge();
      s.dispose();
      final restarted = serviceFor(api..current = 2);
      await restarted.check();
      expect(restarted.notice, CodeUpdateNotice.applied);
      expect(restarted.needsPopup, isFalse);
      api.next = 3;
      await restarted.check(force: true);
      expect(restarted.needsPopup, isTrue);
      restarted.dispose();
    },
  );

  test('a new patch downloads automatically; concurrent checks do not duplicate it', () async {
    final api = FakeUpdater()
      ..result = UpdateStatus.outdated
      ..downloadGate = Completer<void>();
    final s = serviceFor(api);
    final states = <CodeUpdateStatus>[];
    s.addListener(() => states.add(s.status));
    final started = s.check();
    for (var i = 0; i < 30 && api.downloads == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(api.downloads, 1);
    await s.check(force: true);
    expect(s.status, CodeUpdateStatus.downloading);
    api.downloadGate!.complete();
    await started;
    expect(api.downloads, 1);
    expect(
      states,
      containsAllInOrder([
        CodeUpdateStatus.available,
        CodeUpdateStatus.downloading,
        CodeUpdateStatus.ready,
      ]),
    );
    expect(s.nextPatch, 1);
    s.dispose();
  });

  test(
    'unsupported installs and offline failures are never called up to date',
    () async {
      final unsupported = serviceFor(FakeUpdater()..available = false);
      await unsupported.check();
      expect(unsupported.status, CodeUpdateStatus.unsupported);
      expect(unsupported.notice, CodeUpdateNotice.unsupported);
      unsupported.dispose();
      final offline = serviceFor(FakeUpdater()..failCheck = true);
      await offline.check();
      expect(offline.status, CodeUpdateStatus.error);
      expect(offline.notice, isNull);
      offline.dispose();
      final badRead = serviceFor(
        FakeUpdater()
          ..current = 4
          ..failReadNext = true,
      );
      await badRead.check();
      expect(badRead.status, CodeUpdateStatus.error);
      expect(badRead.notice, isNull);
      badRead.dispose();
    },
  );

  test('download failure does not promise a completed update', () async {
    final s = serviceFor(
      FakeUpdater()
        ..result = UpdateStatus.outdated
        ..failDownload = true,
    );
    await s.check();
    expect(s.status, CodeUpdateStatus.error);
    expect(s.nextPatch, isNull);
    expect(s.needsPopup, isFalse);
    s.dispose();
  });

  test('base install is neutral and release versions separate patch notice identities', () async {
    final api = FakeUpdater();
    final base = serviceFor(api);
    await base.check();
    expect(base.status, CodeUpdateStatus.current);
    expect(base.needsPopup, isFalse);
    api.next = 1;
    await base.check(force: true);
    await base.acknowledge();
    final newerRelease = serviceFor(api, version: '1.0.4+5');
    await newerRelease.check();
    expect(newerRelease.needsPopup, isTrue);
    base.dispose();
    newerRelease.dispose();
  });

  test(
    'ordinary repeated checks are throttled but manual checks work',
    () async {
      final api = FakeUpdater();
      final s = serviceFor(api);
      await s.check();
      await s.check();
      expect(api.checks, 1);
      await s.check(force: true);
      expect(api.checks, 2);
      s.dispose();
    },
  );
}
