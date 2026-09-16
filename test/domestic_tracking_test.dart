import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/domestic_tracking_text.dart';
import 'package:lkgroup_app/screens/domestic_tracking_screen.dart';
import 'package:lkgroup_app/services/domestic_tracking_service.dart';

void main() {
  testWidgets(
    'statement search uses route/year/voyage/receipt without a carrier',
    (tester) async {
      Map<String, dynamic>? selection;
      int submitted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DomesticStatementFields(
              language: AppLanguage.korean,
              loadBatches: () async => [
                {'route': '한국->라오스 해상', 'shipment_year': 2026, 'voyage': '09'},
                {'route': '한국->라오스 해상', 'shipment_year': 2025, 'voyage': '07'},
              ],
              onChanged: (value) => selection = value,
              onSubmitted: () => submitted++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('운송경로'), findsOneWidget);
      expect(find.text('배송업체'), findsNothing);
      await tester.enterText(find.byType(TextField), 'LKS 08');
      expect(selection, {
        'route': '한국->라오스 해상',
        'shipment_year': 2026,
        'voyage': '09',
        'receipt_number': 'LKS 08',
      });
      expect(submitted, 0);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 1);
      expect(tester.takeException(), isNull);
    },
  );
  test('Laos display crosses midnight independent of device timezone', () {
    expect(
      DomesticTrackingService.laoDate('2026-09-08T20:18:39Z'),
      '2026-09-09 03:18',
    );
    expect(DomesticTrackingService.laoDate(null), '—');
    expect(domesticText(AppLanguage.korean, 'ready_for_pickup'), '도착 · 수령 대기');
    expect(domesticText(AppLanguage.korean, 'delivered'), '배송 완료');
  });
  testWidgets('logged out users see the sign-in explanation without querying', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DomesticTrackingScreen(language: AppLanguage.korean),
      ),
    );
    expect(find.text('로그인 후 조회할 수 있습니다.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
