import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/domestic_tracking_text.dart';
import 'package:lkgroup_app/screens/domestic_tracking_screen.dart';
import 'package:lkgroup_app/services/domestic_tracking_service.dart';
import 'package:lkgroup_app/models/app_user.dart';
import 'package:lkgroup_app/services/shipment_filter_options_service.dart';

void main() {
  testWidgets('filters contain only DB batches and cascade without submitting a search', (tester) async {
    const batches = [
      ShipmentBatchOption(route: 'sea', year: 2026, voyage: '02'),
      ShipmentBatchOption(route: 'sea', year: 2026, voyage: '10'),
      ShipmentBatchOption(route: 'sea', year: 2025, voyage: '01'),
      ShipmentBatchOption(route: 'air', year: 2024, voyage: '03'),
    ];
    await tester.pumpWidget(MaterialApp(home: DomesticTrackingScreen(
      language: AppLanguage.korean, user: const AppUser(id: 'test', role: UserRole.member),
      loadFilterBatches: () async => batches,
    )));
    await tester.pumpAndSettle();
    List<DropdownButton<String>> selects() => tester.widgetList<DropdownButton<String>>(
      find.byType(DropdownButton<String>)).toList();
    List<String?> values(int i) => selects()[i].items!.map((v) => v.value).toList();
    expect(values(0), ['', 'air', 'sea']);
    selects()[0].onChanged!('sea'); await tester.pump();
    expect(values(1), ['', '2026', '2025']);
    selects()[1].onChanged!('2026'); await tester.pump();
    expect(values(2), ['', '10', '02']);
    selects()[2].onChanged!('02'); await tester.pump();
    selects()[0].onChanged!('air'); await tester.pump();
    expect(values(1), ['', '2024']); expect(values(2), ['', '03']);
    final states = tester.stateList<FormFieldState<String>>(find.byType(DropdownButtonFormField<String>)).toList();
    expect(states[1].value, ''); expect(states[2].value, '');
    expect(find.text('조회 가능한 배송 내역이 없습니다. 입력한 번호와 검색 조건을 확인해 주세요.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed batch load is distinct from empty data and can be retried', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: DomesticTrackingScreen(
      language: AppLanguage.korean, user: const AppUser(id: 'test', role: UserRole.member),
      loadFilterBatches: () async { if (calls++ == 0) throw Exception('offline'); return []; },
    )));
    await tester.pumpAndSettle();
    expect(find.text('검색 조건을 불러오지 못했습니다. 다시 시도하거나 번호만으로 조회하세요.'), findsOneWidget);
    await tester.tap(find.text('다시 시도')); await tester.pumpAndSettle();
    expect(find.text('선택할 운송 데이터가 없습니다. 번호만으로 조회할 수 있습니다.'), findsOneWidget);
    expect(calls, 2); expect(tester.takeException(), isNull);
  });
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
