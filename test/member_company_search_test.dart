import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/services/company_verification_service.dart';
import 'package:lkgroup_app/widgets/company_verification.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lkgroup_app/config/supabase_config.dart';
import 'package:lkgroup_app/models/app_user.dart';
import 'package:lkgroup_app/services/shipment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <http.Request>[];
  final responses = <String, dynamic>{};
  setUpAll(() async {
    expect(SupabaseConfig.isConfigured, isTrue,
        reason: 'Run this test with the CI test-only SUPABASE dart-defines.');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://company-search.invalid',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request);
        return http.Response(jsonEncode(responses[request.url.pathSegments.last] ?? []),
            200, request: request, headers: {'content-type': 'application/json'});
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() { calls.clear(); responses.clear(); });
  const member = AppUser(id: 'member', role: UserRole.member,
      name: '회원', phone: '02012345678', company: 'Test Company/테스트회사');

  test('default profile fields query registered company without an invoice', () async {
    responses['search_shipments_by_registered_company'] = [
      {'id': 2, 'consignee_name': '테스트회사', 'consignee_phone': '02012345678', 'receipt_number': 'LKS 0002', 'weight': 23}
    ];
    final rows = await ShipmentService.instance.searchRows(currentUser: member,
        recipient: member.name, phone: member.phone, year: '2026년', voyage: '09항차');
    expect(rows.single['company_match'], isNull);
    expect(rows.single['receipt_number'], 'LKS 0002');
    expect(rows.single['consignee_phone'], '02012345678');
    expect(rows.single['weight'], 23);
    final request = calls.singleWhere((r) => r.url.path.endsWith('search_shipments_by_registered_company'));
    final params = jsonDecode(request.body) as Map;
    expect(params['p_recipient'], member.name);
    expect(params['p_phone'], member.phone);
    expect(params['p_year'], 2026);
    expect(params['p_voyage'], '09');
    expect(params.containsKey('p_company'), isFalse);
  });
  test('full owned rows and invoice recovery win over masked company duplicates', () async {
    responses['search_shipments_for_current_user'] = [{'id': 1, 'consignee_name': 'Owner'}];
    responses['search_shipments_by_invoice_suffix'] = [{'id': 2, 'invoice_suffix_match': true}];
    responses['search_shipments_by_registered_company'] = [
      {'id': 1, 'company_match': true}, {'id': 2, 'company_match': true}, {'id': 3, 'company_match': true}
    ];
    final rows = await ShipmentService.instance.searchRows(currentUser: member, invoice: '1234');
    expect(rows.length, 3);
    expect(rows[0]['consignee_name'], 'Owner');
    expect(rows[0]['company_match'], isNull);
    expect(rows[1]['invoice_suffix_match'], isTrue);
    expect(rows[2]['company_match'], isTrue);
  });
  test('company status and review use DB RPCs without client-supplied identity', () async {
    responses['my_company_verification'] = {'id': 7, 'status': 'pending', 'company': 'Company'};
    expect((await CompanyVerificationService.mine())['status'], 'pending');
    await CompanyVerificationService.review(7, 'approve');
    final request = calls.last;
    expect(request.url.path, endsWith('admin_review_company_verification'));
    expect(jsonDecode(request.body), {'p_request_id': 7, 'p_action': 'approve'});
  });
  testWidgets('administrator reviews matching company cargo before approving', (tester) async {
    responses['admin_list_company_verifications'] = [
      {'id': 7, 'member_name': '회원', 'member_phone': '02012345678', 'company': '테스트회사', 'email': 'member@example.test', 'status': 'pending', 'match_count': 12,
       'matches': [{'consignee_name': '테스트회사', 'consignee_phone': '02055555555', 'customer_codes': ['123'], 'cargo_count': 12}]}
    ];
    await tester.pumpWidget(const MaterialApp(home: CompanyVerificationScreen(language: AppLanguage.korean)));
    await tester.pumpAndSettle();
    expect(find.text('회사명 일치 화물: 12'), findsOneWidget);
    expect(find.textContaining('LK 0123'), findsOneWidget);
    await tester.tap(find.text('일치 확인·승인'));
    await tester.pumpAndSettle();
    expect(find.textContaining('이 회원과 회사의 관계를 확인했습니까?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '일치 확인·승인').last);
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.url.path.endsWith('admin_review_company_verification')).length, 1);
    await tester.pumpWidget(const SizedBox());
  });

}
