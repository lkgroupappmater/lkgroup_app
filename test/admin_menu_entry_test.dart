// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'package:lkgroup_app/services/live_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lkgroup_app/screens/member_management_screen.dart';
import 'package:lkgroup_app/screens/support_screen.dart';
import 'package:lkgroup_app/screens/voyage_total_management_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <http.Request>[];
  final responses = <String, dynamic>{};
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://company-search.invalid', publishableKey: 'test-key',
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

  testWidgets('members load on entry and ID management is a prominent body card', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    responses['profiles'] = [{'id': 'm1', 'name': 'Visible member', 'role': 'member'}];
    await tester.pumpWidget(const MaterialApp(home: MemberManagementScreen()));
    await tester.pumpAndSettle();
    expect(calls.any((r) => r.url.path.endsWith('/profiles')), isTrue);
    expect(find.textContaining('Visible member'), findsOneWidget);
    expect(find.byKey(const Key('member-customer-id-management')), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('고객 ID 관리')), findsNothing);
    final before = calls.length;
    LiveDataService.instance.topics = {'profiles','shipments'};
    LiveDataService.instance.notifyListeners();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(calls.length, before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manager inbox loads on entry without acknowledging requests', (tester) async {
    responses['list_support_requests'] = {'rows': [], 'has_more': false};
    await tester.pumpWidget(const MaterialApp(home: SupportInboxScreen(manager: true)));
    await tester.pumpAndSettle();
    final request = calls.firstWhere((r) => r.url.path.endsWith('/list_support_requests'));
    expect(jsonDecode(request.body)['p_manager'], isTrue);
    expect(jsonDecode(request.body)['p_search'], '');
    expect(calls.any((r) => r.url.path.endsWith('/open_support_request')), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('voyage totals show saved results without fetching or recalculating cargo', (tester) async {
    responses['admin_excel_bulk_batches'] = [
      {'route': 'Sea', 'shipment_year': 2026, 'voyage': '09'},
    ];
    responses['voyage_settlement_snapshots'] = [
      {'id': 1, 'route_key': 'sea', 'route_label': 'Sea', 'shipment_year': 2026,
        'voyage': '09', 'gross_usd': 20, 'discount_usd': 2, 'net_usd': 18,
        'calculated_at': '2026-10-17'},
    ];
    await tester.pumpWidget(const MaterialApp(home: VoyageTotalManagementScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sea · 2026 · 09'), findsOneWidget);
    expect(find.textContaining('18'), findsWidgets);
    expect(calls.any((r) => r.url.path.endsWith('/admin_excel_bulk_rows')), isFalse);
    expect(calls.any((r) => r.url.path.endsWith('/admin_save_voyage_settlement_snapshot')), isFalse);
    final request = calls.singleWhere((r) => r.url.path.endsWith('/voyage_settlement_snapshots'));
    expect(request.url.queryParameters['select'], isNot(contains('receipts')));
    final before = calls.length;
    LiveDataService.instance.topics = {'profiles','shipments'};
    LiveDataService.instance.notifyListeners();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(calls.length, before);
    await tester.pumpWidget(const SizedBox());
  });
}
