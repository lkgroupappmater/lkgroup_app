import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/core/app_language.dart';
import '../lib/widgets/code_update_panel.dart';
import 'code_update_service_test.dart' show FakeUpdater, serviceFor;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'ready popup appears once and closing it never restarts the app',
    (tester) async {
      final api = FakeUpdater()..next = 2;
      final service = serviceFor(api);
      await service.check();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showCodeUpdateNotice(context, service, AppLanguage.korean),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Patch 2'), findsOneWidget);
      expect(find.textContaining('작업을 저장'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.needsPopup, isFalse);
      expect(api.downloads, 0);
      service.dispose();
    },
  );

  testWidgets(
    'notification details expose the real version and unsupported status',
    (tester) async {
      final service = serviceFor(FakeUpdater()..available = false);
      await service.check();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CodeUpdatePanel(
              language: AppLanguage.korean,
              service: service,
            ),
          ),
        ),
      );
      expect(find.textContaining('1.0.3+4'), findsOneWidget);
      expect(find.textContaining('지원하지 않습니다'), findsOneWidget);
      expect(find.text('업데이트 확인'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );
}
