import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/domestic_tracking_text.dart';
import 'package:lkgroup_app/screens/domestic_tracking_screen.dart';
import 'package:lkgroup_app/services/domestic_tracking_service.dart';
import 'package:lkgroup_app/models/app_user.dart';

void main() {
  test('carrier detection is conservative and leaves numeric ANS candidates for confirmation', () {
    expect(DomesticTrackingService.detectCarrier('vte12345678901'), 'HAL');
    expect(DomesticTrackingService.detectCarrier('JTLA123456789012'), 'JT');
    expect(DomesticTrackingService.detectCarrier('VT123-12345-12345'), 'MIXAY');
    expect(DomesticTrackingService.detectCarrier('VT1231234512345'), 'MIXAY');
    expect(DomesticTrackingService.detectCarrier('1234567890123'), isNull);
    expect(DomesticTrackingService.isAnsCandidate('1234567890123'), isTrue);
    expect(DomesticTrackingService.detectCarrier('VTE123'), isNull);
  });
  testWidgets('customer search begins with a statement and transport filters, without carrier names', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DomesticTrackingScreen(
      language: AppLanguage.korean, user: AppUser(id: 'test', role: UserRole.member))));
    await tester.pump();
    expect(find.text('명세서 번호 / 화물번호'), findsOneWidget);
    expect(find.text('운송경로'), findsOneWidget);
    expect(find.textContaining('HAL'), findsNothing);
    expect(find.textContaining('ANS'), findsNothing);
    expect(find.textContaining('Mixay'), findsNothing);
    expect(find.textContaining('J&T'), findsNothing);
    expect(find.text('송장 등록'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
