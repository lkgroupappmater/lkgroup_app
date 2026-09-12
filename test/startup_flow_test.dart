import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app.dart';
import '../lib/screens/splash_screen.dart';
import '../lib/widgets/app_shell.dart';

final standaloneGroupLogo = find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName ==
          'assets/images/lk_group_logo.png',
);

Future<void> prepareWelcome(WidgetTester tester) async {
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/images/company_splash_logo.png'),
      tester.element(find.byType(CompanySplashLogo)),
    );
  });
  // The welcome screen has a continuously animated progress indicator.
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.otf'))).load();
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets(
      'welcome is the first Flutter screen at ${size.width} x ${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 24);
        addTearDown(tester.view.reset);
        final pending = Completer<void>();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: CargoFlowApp(
              initialize: () {
                expect(find.byType(CompanySplashLogo), findsOneWidget);
                return pending.future;
              },
            ),
          ),
        );
        // No separate group-logo screen, even before image decoding completes.
        expect(standaloneGroupLogo, findsNothing);
        expect(find.text('Welcome!'), findsOneWidget);
        await prepareWelcome(tester);
        expect(find.byType(CompanySplashLogo), findsOneWidget);
        expect(find.text('By LK Group'), findsOneWidget);
        final image = tester.widget<Image>(
          find.descendant(
            of: find.byType(CompanySplashLogo),
            matching: find.byType(Image),
          ),
        );
        expect(image.fit, BoxFit.contain);
        final rect = tester.getRect(find.byType(CompanySplashLogo));
        expect(rect.left, greaterThanOrEqualTo(24));
        expect(rect.right, lessThanOrEqualTo(size.width - 24));
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final snapshot = await render.toImage();
          final data = await snapshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final file = File(
            'build/startup-previews/welcome-${size.width.toInt()}x${size.height.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          snapshot.dispose();
        });
        // Short displays keep the existing scrollable welcome layout.
        await tester.ensureVisible(find.text('By LK Group'));
        await tester.pump();
        final footer = tester.getRect(find.text('By LK Group'));
        expect(footer.left, greaterThanOrEqualTo(24));
        expect(footer.right, lessThanOrEqualTo(size.width - 24));
        await tester.pump(const Duration(seconds: 10));
        expect(standaloneGroupLogo, findsNothing);
        expect(find.byType(AppShell), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        pending.complete();
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'services wait for the welcome first frame without a logo delay',
    (tester) async {
      final frame = Completer<void>();
      final initialized = Completer<void>();
      var startedServices = 0;
      await tester.pumpWidget(
        CargoFlowApp(
          onWelcomeReady: () => frame.future,
          initialize: () {
            startedServices++;
            return initialized.future;
          },
        ),
      );
      await prepareWelcome(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(standaloneGroupLogo, findsNothing);
      expect(find.byType(CompanySplashLogo), findsOneWidget);
      expect(startedServices, 0);
      frame.complete();
      await tester.pump();
      expect(startedServices, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(startedServices, 1);
      expect(standaloneGroupLogo, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      initialized.complete();
      await tester.pump();
    },
  );

  testWidgets(
    'failed initialization shows a connection error instead of entering an uninitialized home',
    (tester) async {
      await tester.pumpWidget(
        CargoFlowApp(
          initialize: () async {
            throw Exception('unavailable');
          },
        ),
      );
      await prepareWelcome(tester);
      expect(find.textContaining('서비스에 연결하지 못했습니다'), findsOneWidget);
      expect(standaloneGroupLogo, findsNothing);
      expect(find.byType(AppShell), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
