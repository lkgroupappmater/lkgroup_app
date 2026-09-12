import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app.dart';
import '../lib/screens/splash_screen.dart';
import '../lib/widgets/app_shell.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets(
      'full group logo and waiting screen fit ${size.width} x ${size.height}',
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
                expect(find.byType(GroupLaunchLogo), findsOneWidget);
                return pending.future;
              },
            ),
          ),
        );
        await tester.runAsync(() async {
          final context = tester.element(find.byType(GroupLaunchLogo));
          await precacheImage(
            const AssetImage('assets/images/lk_group_logo.png'),
            context,
          );
          await precacheImage(
            const AssetImage('assets/images/company_splash_logo.png'),
            context,
          );
        });
        await tester.pumpAndSettle();
        expect(find.byType(CompanySplashLogo), findsNothing);
        final image = tester.widget<Image>(
          find.descendant(
            of: find.byType(GroupLaunchLogo),
            matching: find.byType(Image),
          ),
        );
        expect(
          (image.image as AssetImage).assetName,
          'assets/images/lk_group_logo.png',
        );
        final rect = tester.getRect(find.byType(GroupLaunchLogo));
        expect(rect.left, greaterThanOrEqualTo(32));
        expect(rect.right, lessThanOrEqualTo(size.width - 32));
        expect(rect.top, greaterThanOrEqualTo(44));
        expect(rect.bottom, lessThanOrEqualTo(size.height - 24));
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final snapshot = await render.toImage();
          final data = await snapshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final file = File(
            'build/startup-previews/group-${size.width.toInt()}x${size.height.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          snapshot.dispose();
        });
        await tester.pump(const Duration(milliseconds: 1200));
        expect(find.byType(GroupLaunchLogo), findsNothing);
        expect(find.byType(CompanySplashLogo), findsOneWidget);
        expect(find.text('By LK Group'), findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
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
    'failed initialization shows a connection error instead of entering an uninitialized home',
    (tester) async {
      await tester.pumpWidget(
        CargoFlowApp(
          initialize: () async {
            throw Exception('unavailable');
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      expect(find.textContaining('서비스에 연결하지 못했습니다'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
