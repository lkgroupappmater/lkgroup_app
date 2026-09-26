import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/app_language.dart';
import '../lib/screens/customer_registry_screen.dart';
import '../lib/screens/customer_registry_bulk_editor.dart';
import '../lib/services/domestic_tracking_service.dart';

final rows = List.generate(4, (i) => <String, dynamic>{'id': 'customer$i', 'customer_no': i + 3, 'customer_code': '00${i + 3}', 'name': 'Customer $i', 'phone': i == 0 ? '' : '0201111000$i', 'source_count': 1, 'updated_at': '2026-09-26T00:00:00Z', 'duplicates': <dynamic>[]});
void largeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 6000); tester.view.devicePixelRatio = 1;
  addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
}
void main() {
  testWidgets('search remains visible while customer rows scroll, and name/phone taps run searches', (tester) async {
    tester.view.physicalSize = const Size(400, 750); tester.view.devicePixelRatio = 1;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    final queries = <Map<String, dynamic>>[];
    final many = List.generate(30, (i) => {...rows[1], 'id': 'row$i', 'name': 'Name $i', 'phone': '0201111${i.toString().padLeft(4, '0')}'});
    await tester.pumpWidget(MaterialApp(home: CustomerRegistryScreen(callApi: (action, body) async { queries.add(body); return {'customers': many, 'total': 30, 'summary': {'customers': 30}, 'has_more': false}; })));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const ValueKey('registry-search')));
    await tester.drag(find.byKey(const ValueKey('registry-list')), const Offset(0, -700)); await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('registry-search'))), before);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('quick-name-row10')), 250, scrollable: find.descendant(of: find.byKey(const ValueKey('registry-list')), matching: find.byType(Scrollable)));
    await tester.tap(find.byKey(const ValueKey('quick-name-row10'))); await tester.pumpAndSettle();
    expect(queries.last['query'], 'Name 10'); expect(queries.last['conflicts_only'], false);
    await tester.tap(find.byKey(const ValueKey('quick-phone-row1'))); await tester.pumpAndSettle();
    expect(queries.last['query'], '0001'); expect(tester.takeException(), isNull);
  });
  testWidgets('selected contacts save together with no required reason', (tester) async {
    largeView(tester); final writes = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: CustomerRegistryScreen(callApi: (action, body) async {
      if (action == 'customers_list') return {'customers': rows, 'total': rows.length, 'summary': {'customers': rows.length}, 'has_more': false};
      expect(action, 'customers_bulk'); writes.add(body); return {'updated_count': 2};
    })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-customer0'))); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('select-customer1'))); await tester.pump();
    await tester.tap(find.text('선택 항목 일괄 수정')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('phone-customer0')), '02099990000');
    await tester.enterText(find.byKey(const ValueKey('phone-customer1')), '02099990001 / 02099990002');
    await tester.tap(find.byKey(const ValueKey('bulk-save'))); await tester.pumpAndSettle();
    expect(writes, hasLength(1)); expect(writes.single['reason'], ''); expect(writes.single['confirmed'], true);
    final saved = writes.single['rows'] as List;
    expect(saved, hasLength(2)); expect(saved[0]['phone'], '02099990000'); expect(saved[1]['phone'], '02099990001 / 02099990002');
    expect(find.text('선택 항목 저장 완료'), findsOneWidget); expect(tester.takeException(), isNull);
  });
  testWidgets('common merge needs review and failure retains edited phone', (tester) async {
    largeView(tester); final writes = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: CustomerRegistryBulkEditor(rows: rows.take(2).toList(), language: AppLanguage.korean, merge: true, callApi: (action, body) async {
      writes.add(body); throw const DomesticTrackingException('RECORD_CHANGED');
    })));
    await tester.tap(find.byKey(const ValueKey('common-target'))); await tester.pumpAndSettle();
    await tester.tap(find.text('004 · Customer 1 · 02011110001').last); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('bulk-save'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('bulk-reviewed'))); await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('phone-customer1')), '02077770000'); await tester.pump();
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('bulk-reviewed'))).value, false);
    await tester.tap(find.byKey(const ValueKey('bulk-reviewed'))); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-save'))); await tester.pumpAndSettle();
    expect(writes, hasLength(1)); expect((writes.single['rows'] as List).map((r) => r['target_id']), ['customer1', 'customer1']);
    expect(find.text('02077770000'), findsOneWidget); expect(find.textContaining('다른 곳에서 자료가 변경'), findsOneWidget); expect(tester.takeException(), isNull);
  });
}
