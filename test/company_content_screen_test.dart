import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/app_language.dart';
import '../lib/screens/company_content_screen.dart';
import '../lib/services/content_service.dart';
import '../lib/widgets/content_media.dart';

void main() {
  final articles = <Map<String, dynamic>>[
    {
      'id': 'a',
      'category': 'activity',
      'title': '활동 기록',
      'summary': '현장 소식',
      'body': '본문',
      'event_date': '2026-09-05',
    },
    {
      'id': 'b',
      'category': 'csr',
      'title': '교육 지원',
      'summary': '학교 소식',
      'body': '교육 본문',
      'original_published_at': '2025-12-03',
    },
  ];
  testWidgets('a category opens its list and clears a prior search', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyContentScreen(
          language: AppLanguage.korean,
          loadArticles: () async => articles,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '활동');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('교육 지원'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('company-category-a')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('company-filter-activity')),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('활동 기록'), findsOneWidget);
  });
  testWidgets('detail category closes the article and opens its category', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyContentScreen(
          language: AppLanguage.korean,
          loadArticles: () async => articles,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('원게시일: 2025-12-03'), findsOneWidget);
    await tester.tap(find.text('교육 지원'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-company-category')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('company-filter-csr')), findsOneWidget);
    expect(find.text('활동 기록'), findsNothing);
  });
  test('content chronology uses the event date before publication dates', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'old', 'event_date': '2024-02-18', 'published_at': '2026-09-15'},
      {'id': 'new', 'original_published_at': '2025-12-03'},
    ]..sort(ContentService.compareCompanyArticles);
    expect(rows.first['id'], 'new');
  });
  test('website source photos use their public site path', () async {
    expect(
      await contentMediaUrl({
        'path': 'site:company/case-ict.webp',
      }, 'website-content'),
      'https://lkgrouptrading.com/assets/company/case-ict.webp',
    );
  });
}
