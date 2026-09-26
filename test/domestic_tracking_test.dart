import 'package:lkgroup_app/screens/waybill_intake_screen.dart';
import 'package:lkgroup_app/services/waybill_intake_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/domestic_tracking_text.dart';
import 'package:lkgroup_app/screens/domestic_tracking_screen.dart';
import 'package:lkgroup_app/services/domestic_tracking_service.dart';
import 'package:lkgroup_app/models/app_user.dart';
import 'package:lkgroup_app/services/shipment_filter_options_service.dart';

void main() {
  Future<void> choose(WidgetTester tester, String value) async {
    final dropdown = tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
      .firstWhere((w) => w.items!.any((item) => item.value == value));
    dropdown.onChanged!(value); await tester.pump();
  }
  Future<void> editor(WidgetTester tester, Future<Map<String, dynamic>> Function(String, Map<String, dynamic>) call, {Future<List<DomesticPhotoSelection>> Function()? pickPhotos}) async {
    tester.view.physicalSize = const Size(1000, 2600); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: DomesticWaybillEditor(language: AppLanguage.korean,
      loadFilterBatches: () async => const [ShipmentBatchOption(route: 'sea', year: 2026, voyage: '08'), ShipmentBatchOption(route: 'sea', year: 2026, voyage: '09')], callApi: call, pickPhotos: pickPhotos)));
    await tester.pumpAndSettle();
  }
  Future<void> enterStatement(WidgetTester tester) async {
    await choose(tester, 'sea'); await choose(tester, '2026'); await choose(tester, '08');
    await tester.enterText(find.byKey(const Key('delivery-receipt-number')), 'LKS 03');
    await tester.enterText(find.byKey(const Key('delivery-tracking-number')), 'VTE12345678901');
    await choose(tester, 'HAL');
  }
  const statement = {'route':'sea','shipment_year':2026,'voyage':'08','receipt_number':'LKS 03'};
  testWidgets('statement confirmation is required and the canonical LK receipt stays separate from the waybill', (tester) async {
    final calls = <Map<String, dynamic>>[];
    await editor(tester, (action, body) async {
      calls.add({'action':action, ...body});
      if (action == 'statement_resolve') return {'statement':statement,'cargo_count':2,'cargo':[]};
      return {'parcels':[{}]};
    });
    await enterStatement(tester);
    await tester.tap(find.byKey(const Key('delivery-save'))); await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text(domesticText(AppLanguage.korean, 'STATEMENT_REQUIRED')), findsOneWidget);
    await tester.tap(find.byKey(const Key('delivery-confirm-statement'))); await tester.pumpAndSettle();
    expect(calls.single['receipt_number'], 'LKS 03');
    await choose(tester, '09');
    await tester.tap(find.byKey(const Key('delivery-save'))); await tester.pumpAndSettle();
    expect(calls.length, 1);
    await choose(tester, '08');
    await tester.tap(find.byKey(const Key('delivery-confirm-statement'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delivery-save'))); await tester.pumpAndSettle();
    expect(calls.last['action'], 'save_batch'); expect(calls.last['link_scope'], 'statement');
    expect(calls.last['statement'], statement); expect(calls.last['shipment_id'], isNull);
    expect(calls.last['tracking_number'], 'VTE12345678901'); expect(tester.takeException(), isNull);
  });
  testWidgets('ecommerce references save without an international cargo selection', (tester) async {
    final calls = <Map<String, dynamic>>[];
    await editor(tester, (action, body) async { calls.add({'action':action, ...body}); return {'parcels':[{}]}; });
    await choose(tester, 'reference');
    await tester.enterText(find.byKey(const Key('delivery-reference-number')), 'EC-003');
    await tester.enterText(find.byKey(const Key('delivery-tracking-number')), 'VTE12345678901'); await choose(tester, 'HAL');
    await tester.tap(find.byKey(const Key('delivery-save'))); await tester.pumpAndSettle();
    expect(calls.single['reference'], {'reference_type':'ecommerce','reference_number':'EC-003'});
    expect(calls.single['service_kind'], 'ecommerce'); expect(calls.single['shipment_id'], isNull);
    expect(calls.single['statement'], isNull); expect(tester.takeException(), isNull);
  });
  testWidgets('late confirmation cannot link the receipt that the operator has already changed', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await editor(tester, (action, body) => pending.future);
    await enterStatement(tester);
    await tester.tap(find.byKey(const Key('delivery-confirm-statement'))); await tester.pump();
    await tester.enterText(find.byKey(const Key('delivery-receipt-number')), 'LKS 04');
    pending.complete({'statement':statement,'cargo_count':2,'cargo':[]}); await tester.pumpAndSettle();
    expect(find.textContaining(domesticText(AppLanguage.korean, 'statementConfirmed')), findsNothing);
    await tester.tap(find.byKey(const Key('delivery-save'))); await tester.pumpAndSettle();
    expect(find.text(domesticText(AppLanguage.korean, 'STATEMENT_REQUIRED')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('selected photos open shared review with the confirmed statement and never save automatically', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final image = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ZkAAAAASUVORK5CYII=');
    await editor(tester, (action, body) async {
      calls.add({'action': action, ...body});
      if (action == 'statement_resolve') return {'statement': statement, 'cargo_count': 1, 'cargo': []};
      return {'parcels': [{}, {}]};
    }, pickPhotos: () async => [DomesticPhotoSelection('one.png', image), DomesticPhotoSelection('two.png', image)]);
    await enterStatement(tester);
    await tester.tap(find.byKey(const Key('delivery-confirm-statement'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delivery-add-waybill'))); await tester.pumpAndSettle();
    final numbers = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == domesticText(AppLanguage.korean, 'tracking'));
    await tester.enterText(numbers.last, 'JTLA123456789012'); await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('delivery-pick-photos')));
    await tester.tap(find.byKey(const Key('delivery-pick-photos'))); await tester.pumpAndSettle();
    final screen=tester.widget<WaybillIntakeScreen>(find.byType(WaybillIntakeScreen));
    expect(screen.files.map((f)=>f.name), ['one.png','two.png']);
    expect(screen.fixedLink?['statement'], statement);
    expect(calls.any((c)=>c['action']=='save_batch'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reference photos attach to a confirmed statement without requiring a waybill number', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final image = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ZkAAAAASUVORK5CYII=');
    await editor(tester, (action, body) async {
      calls.add({'action':action,...body});
      return {'statement':statement,'cargo_count':1,'cargo':[]};
    }, pickPhotos: () async => [DomesticPhotoSelection('box.png', image)]);
    await choose(tester,'sea'); await choose(tester,'2026'); await choose(tester,'08');
    await tester.enterText(find.byKey(const Key('delivery-receipt-number')),'LKS 03');
    await tester.tap(find.byKey(const Key('delivery-confirm-statement'))); await tester.pumpAndSettle();
    tester.widget<DropdownButton<bool>>(find.byType(DropdownButton<bool>)).onChanged!(true); await tester.pump();
    expect(find.byKey(const Key('delivery-tracking-number')),findsNothing);
    await tester.ensureVisible(find.byKey(const Key('delivery-save')));
    await tester.tap(find.byKey(const Key('delivery-save'))); await tester.pumpAndSettle();
    final screen=tester.widget<WaybillIntakeScreen>(find.byType(WaybillIntakeScreen));
    expect(screen.referenceOnly,isTrue);expect(screen.fixedLink?['statement'],statement);
    expect(screen.files.single.name,'box.png');expect(calls.any((c)=>c['action']=='save_batch'),isFalse);
    expect(tester.takeException(),isNull);
  });
  test('intake validates 50 images at 5MB each and rejects excess before reading bytes',(){
    final file=IntakeFile('photo.jpg',5242880,()async=>throw StateError('must not read'));
    expect(()=>WaybillIntakeService.validate(List.filled(50,file)),returnsNormally);
    expect(()=>WaybillIntakeService.validate(List.filled(51,file)),throwsA(isA<DomesticTrackingException>()));
    expect(()=>WaybillIntakeService.validate([IntakeFile('too-large.jpg',5242881,file.readBytes)]),throwsA(isA<DomesticTrackingException>()));
  });
  testWidgets('management keeps grouped results until an explicit refresh', (tester) async {
    tester.view.physicalSize = const Size(1000, 3200); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final actions = <String>[];
    final parcels = List.generate(2, (i) => <String,dynamic>{'id':'id$i','group_key':'same-statement','statement':statement,'carrier_name':'HAL','carrier':'HAL','tracking_number':'VTE1234567890$i','delivery_kind':'province','service_kind':'domestic','status':'delivered','integration':'auto','events':[],'photo_urls':[],'receiver_name':'원*연','receiver_phone':'020 5555 ****','recipient_masked':true,'origin':'','destination':'','can_manage':false});
    await tester.pumpWidget(MaterialApp(home: DomesticTrackingScreen(language: AppLanguage.korean,
      user: const AppUser(id:'test',role:UserRole.admin), manage:true, loadFilterBatches: () async => [],
      callApi: (action, body) async { actions.add(action); return {'parcels':parcels,'has_more':false}; })));
    await tester.pumpAndSettle();
    expect(actions, ['list_groups']); expect(find.byKey(const ValueKey('statement-group-same-statement')), findsOneWidget);
    expect(find.text('LK 명세서 번호: LKS 03'), findsOneWidget);
    expect(find.text('수취인 전화번호: 020 5555 ****'), findsWidgets);
    await tester.pump(const Duration(minutes:5)); await tester.pumpAndSettle();
    expect(actions, ['list_groups']);
    await tester.tap(find.text(domesticText(AppLanguage.korean, 'list')));
    await tester.pumpAndSettle();
    expect(actions, ['list_groups','list_groups']);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
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
      find.byType(DropdownButton<String>)).where((w) => !w.items!.any((item) => item.value == 'statement')).toList();
    List<String?> values(int i) => selects()[i].items!.map((v) => v.value).toList();
    expect(values(0), ['', 'air', 'sea']);
    selects()[0].onChanged!('sea'); await tester.pump();
    expect(values(1), ['', '2026', '2025']);
    selects()[1].onChanged!('2026'); await tester.pump();
    expect(values(2), ['', '10', '02']);
    selects()[2].onChanged!('02'); await tester.pump();
    selects()[0].onChanged!('air'); await tester.pump();
    expect(values(1), ['', '2024']); expect(values(2), ['', '03']);
    final states = tester.stateList<FormFieldState<String>>(find.byType(DropdownButtonFormField<String>)).where((s) => s.widget.key != null).toList();
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

