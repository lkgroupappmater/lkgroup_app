import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/domestic_tracking_text.dart';
import 'package:lkgroup_app/core/shared_ui_text_catalog.dart';
import 'package:lkgroup_app/models/app_user.dart';
import 'package:lkgroup_app/screens/domestic_tracking_screen.dart';
import 'package:lkgroup_app/services/shared_ui_text_service.dart';

void main() {
  tearDown(() => SharedUiTextService.instance.applyRows([]));

  test('one title key and all three saved languages drive app and web aliases', () {
    final service = SharedUiTextService.instance;
    service.applyRows([{'key':'domesticTracking', 'ko':'새 제목', 'en':'New title', 'lo':'ຫົວຂໍ້ໃໝ່'}]);
    for (final lang in AppLanguage.values) {
      expect(domesticText(lang, 'title'), ['새 제목', 'New title', 'ຫົວຂໍ້ໃໝ່'][lang.index]);
    }
    expect(domesticText(AppLanguage.korean, 'manage'), '새 제목');
    service.applyRows([]);
    expect(domesticText(AppLanguage.korean, 'title'), '라오스 국내 배송 조회 & 관리 (e-commerce)');
  });

  test('legacy keys resolve deterministically without changing unrelated copy', () {
    final service = SharedUiTextService();
    service.applyRows([
      {'key':'domesticTracking','ko':'old','updated_at':'2026-09-17T01:00:00Z'},
      {'key':'domestic.title','ko':'new','updated_at':'2026-09-17T02:00:00Z'},
      {'key':'private-customer-name','ko':'must not become a label'},
    ]);
    expect(service.text('domesticTracking','ko','fallback'), 'new');
    expect(service.text('private-customer-name','ko','fallback'), 'fallback');
    service.dispose();
  });

  test('common labels use the shared key and empty translations use shared defaults', () {
    final service = SharedUiTextService.instance;
    service.applyRows([{'key':'route','ko':'공통 경로','en':'','lo':''}]);
    expect(AppStrings.get(AppLanguage.korean, 'route'), '공통 경로');
    expect(AppStrings.get(AppLanguage.english, 'route'), sharedTextDefaults['route']!['en']);
    expect(service.korean('임의 고객 메모','ko','임의 고객 메모'), '임의 고객 메모');
  });

  test('pagination applies only complete snapshots and deletions restore defaults', () async {
    var fail = false, empty = false;
    final offsets = <int>[];
    final service = SharedUiTextService(loadPage: (offset, limit) async {
      offsets.add(offset);
      if (empty) return [];
      if (offset == 500 && fail) throw StateError('offline');
      if (offset == 0) return [
        {'key':'domesticTracking','ko':fail ? 'partial' : 'saved'},
        ...List.generate(499, (i) => {'key':'unused$i','ko':''}),
      ];
      return [{'key':'domestic.hint','ko':'saved hint'}];
    });
    expect(await service.refresh(), isTrue);
    expect(offsets, [0,500]);
    expect(service.text('domestic.title','ko','fallback'),'saved');
    fail = true;
    expect(await service.refresh(), isFalse);
    expect(service.text('domestic.title','ko','fallback'),'saved');
    empty = true;
    expect(await service.refresh(), isTrue);
    expect(service.text('domestic.title','ko','fallback'),'라오스 국내 배송 조회 & 관리 (e-commerce)');
    service.dispose();
  });

  test('overlapping refreshes reuse one request and unchanged text does not rebuild', () async {
    final request = Completer<List<Map<String,dynamic>>>();
    var calls = 0, changes = 0;
    final service = SharedUiTextService(loadPage: (_, __) {calls++; return request.future;});
    service.addListener(() => changes++);
    final first = service.refresh(), second = service.refresh();
    request.complete([{'key':'domesticTracking','ko':'saved'}]);
    expect(await first,isTrue); expect(await second,isTrue); expect(calls,1);
    service.applyRows([{'key':'domesticTracking','ko':'saved'}]);
    expect(changes,1);
    service.dispose();
  });

  testWidgets('open lookup title updates without discarding the entered number', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DomesticTrackingScreen(
      language: AppLanguage.korean, user: const AppUser(id:'test',role:UserRole.member),
      loadFilterBatches: () async => [], callApi: (_, __) async => {'parcels':[]},
    )));
    await tester.pumpAndSettle();
    final input = find.byType(TextField).first;
    await tester.enterText(input, 'LKS 03');
    SharedUiTextService.instance.applyRows([{'key':'domestic.publicTitle','ko':'동기화된 제목'}]);
    await tester.pump();
    expect(find.text('동기화된 제목'),findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text,'LKS 03');
    await tester.pumpWidget(const SizedBox());
  });
}


