import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/operational_localizations.dart';
import 'package:lkgroup_app/core/route_catalog.dart';
import 'package:lkgroup_app/core/shipment_period_labels.dart';
import 'package:lkgroup_app/core/shared_ui_text_catalog.dart';
import 'package:lkgroup_app/widgets/management_field_search.dart';
import 'package:lkgroup_app/services/shared_ui_text_service.dart';

void main() {
  test('status and period dropdown labels follow the selected language', () {
    for (final language in AppLanguage.values) {
      for (final status in ['pending', 'reviewing', 'approved', 'rejected', 'completed']) {
        expect(OperationalLocalizations.status(language, status), isNot(status));
      }
    }
    expect(OperationalLocalizations.status(AppLanguage.english, 'custom'), 'custom');
    expect(ShipmentPeriodLabels.voyage('전체', AppLanguage.english), 'All');
    expect(ShipmentPeriodLabels.voyage('09항차', AppLanguage.english), 'Voyage 09');
    expect(ShipmentPeriodLabels.year('2026년', AppLanguage.lao), 'ປີ 2026');
  });
  tearDown(() => SharedUiTextService.instance.applyRows([]));
  test('route names and stable keys display in all three languages', () {
    for (final route in RouteCatalog.definitions) {
      for (final language in [AppLanguage.english, AppLanguage.lao]) {
        final name = RouteCatalog.localizedLabel(route.displayName, language);
        expect(name, isNot(matches(RegExp(r'[가-힣]'))));
        expect(RouteCatalog.localizedLabel(route.routeKey, language), name);
      }
      expect(RouteCatalog.localizedLabel(route.routeKey, AppLanguage.korean), route.displayName);
    }
    expect(RouteCatalog.localizedLabel('한국->라오스 해상', AppLanguage.english), 'Korea → Laos Sea Freight');
    expect(RouteCatalog.localizedLabel('한국 ➜ 태국 항공', AppLanguage.lao), 'ເກົາຫຼີ → ໄທ ທາງອາກາດ');
    expect(RouteCatalog.localizedLabel('all', AppLanguage.english), 'All');
    expect(RouteCatalog.localizedLabel('custom-route', AppLanguage.english), 'custom-route');
  });
  test('fixed UI templates preserve customer content and literal placeholders', () {
    for (final language in [AppLanguage.english, AppLanguage.lao]) {
      const name = '김요셉 {p1} / 뷰티판다';
      final translated = OperationalLocalizations.text(language, '$name 수정');
      expect(translated, contains(name));
      expect(translated, isNot(contains('수정')));
      expect(OperationalLocalizations.text(language, '뷰티판다 고객 메모'), '뷰티판다 고객 메모');
      expect(OperationalLocalizations.text(language, '배송 매칭 확인 필요 12건'), isNot(contains('확인 필요')));
    }
  });
  test('new operational defaults have translated EN and Lao with intact parameters', () {
    final variables = RegExp(r'\{\w+\}');
    for (final entry in sharedTextDefaults.entries.where((e) => e.key.startsWith('operations.'))) {
      final ko = entry.value['ko']!;
      for (final code in ['en', 'lo']) {
        final translated = entry.value[code]!;
        expect(translated, isNotEmpty, reason: entry.key);
        expect(RegExp(r'[가-힣]').hasMatch(translated), isFalse, reason: entry.key);
        expect(variables.allMatches(translated).map((m) => m[0]).toSet(),
          variables.allMatches(ko).map((m) => m[0]).toSet(), reason: entry.key);
      }
    }
  });
  testWidgets('field search changes language without discarding the pending query', (tester) async {
    final filter = ManagementFieldFilter();
    Widget screen(AppLanguage language) => MaterialApp(home: Scaffold(body: ManagementFieldSearch(
      language: language, filter: filter, fields: const {'name':'고객명','phone':'연락처'}, onChanged: () {},
    )));
    await tester.pumpWidget(screen(AppLanguage.english));
    expect(find.text('All fields'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '김요셉 LK 0023');
    await tester.pumpWidget(screen(AppLanguage.lao));
    expect(find.text('ທຸກລາຍການ'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '김요셉 LK 0023');
    expect(filter.field, '');
    expect(filter.query, '');
  });
}
