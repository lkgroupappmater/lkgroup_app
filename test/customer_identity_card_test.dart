import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/app_language.dart';
import '../lib/widgets/customer_identity_card.dart';
import '../lib/services/customer_identity_service.dart';

void main() {
  test('customer ID parsing preserves identity and does not strip the statement prefix', () {
    expect(CustomerIdentityService.normalizeCode('23'), '023');
    expect(CustomerIdentityService.normalizeCode('ID 023'), '023');
    expect(CustomerIdentityService.normalizeCode('9023'), '9023');
    expect(CustomerIdentityService.normalizeCode('Hong / Lee'), isNull);
    expect(CustomerIdentityService.normalizeCode('0'), isNull);
  });
  testWidgets('compact header exposes customer ID without opening account settings', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomerIdentityCard(userId: 'member', language: AppLanguage.korean, compact: true, loadIdentity: () async => {'customer_code': '023', 'status': 'linked'}))));
    await tester.pumpAndSettle(); expect(find.text('고객 고유 ID: 023'), findsOneWidget); expect(tester.takeException(), isNull);
  });
  testWidgets('shows the unique customer ID and no invented number for an unmatched member', (tester) async {
    var matched = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomerIdentityCard(userId: 'member', language: AppLanguage.korean, loadIdentity: () async => {'customer_code': matched ? '023' : null, 'status': matched ? 'linked' : 'unmatched'}))));
    await tester.pumpAndSettle(); expect(find.text('고객 고유 ID'), findsOneWidget); expect(find.text('023'), findsOneWidget);
    matched = false; await tester.tap(find.byIcon(Icons.refresh)); await tester.pumpAndSettle();
    expect(find.text('연결된 고객 ID 없음'), findsOneWidget); expect(find.text('023'), findsNothing);
  });
  testWidgets('late response cannot reveal a previous members ID', (tester) async {
    final old = Completer<Map<String, dynamic>>(), current = Completer<Map<String, dynamic>>();
    Widget page(String id, Future<Map<String, dynamic>> result) => MaterialApp(home: Scaffold(body: CustomerIdentityCard(userId: id, language: AppLanguage.korean, loadIdentity: () => result)));
    await tester.pumpWidget(page('old', old.future)); await tester.pumpWidget(page('new', current.future));
    old.complete({'customer_code': '001', 'status': 'linked'}); await tester.pump(); expect(find.text('001'), findsNothing);
    current.complete({'customer_code': '047', 'status': 'linked'}); await tester.pumpAndSettle(); expect(find.text('047'), findsOneWidget); expect(tester.takeException(), isNull);
  });
}
