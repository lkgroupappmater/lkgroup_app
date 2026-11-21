import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lkgroup_app/config/supabase_config.dart';
import 'package:lkgroup_app/models/app_user.dart';
import 'package:lkgroup_app/screens/local_delivery_management_screen.dart';
import 'package:lkgroup_app/screens/discount_management_screen.dart';
import 'package:lkgroup_app/screens/customer_list_management_screen.dart';
import 'package:lkgroup_app/screens/member_management_screen.dart';
import 'package:lkgroup_app/screens/schedule_management_screen.dart';
import 'package:lkgroup_app/screens/notice_management_screen.dart';
import 'package:lkgroup_app/widgets/management_field_search.dart';

// The real screens and Supabase client run against synthetic HTTP responses.
// No production credentials, customers or writes are used.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <http.Request>[];
  final pending = <String, List<Completer<dynamic>>>{};
  var failLists = false;
  const admin = AppUser(id: 'search-test', role: UserRole.admin);
  final screens = <String, Widget Function()>{
    'local_delivery_profiles': () => const LocalDeliveryManagementScreen(),
    'admin_list_discount_rules_with_identity': () => const DiscountManagementScreen(),
    'shipments': () => const CustomerListManagementScreen(),
    'profiles': () => const MemberManagementScreen(),
    'shipping_schedules': () => const ScheduleManagementScreen(user: admin),
    'notices': () => const NoticeManagementScreen(user: admin),
  };
  List<Map<String, dynamic>> rows([List<String> names = const ['Alpha', 'Beta']]) => [
    for (var i = 0; i < names.length; i++) {
      'id': i + 1, 'customer_name': names[i], 'name': names[i],
      'consignee_name': names[i], 'title': names[i], 'detail': names[i],
      'route_key': 'kr_la_sea', 'route': '한국->라오스 해상',
      'shipment_year': 2026, 'year': 2026, 'voyage': '22',
      'phone': '0201234567$i', 'consignee_phone': '0201234567$i',
      'receipt_number': 'LKS${i + 1}', 'box_number': '${i + 1}',
      'unloading_zone': 'A', 'quantity': 1, 'source_no': i + 1,
      'local_company': 'HAL', 'destination_address': 'Vientiane',
      'delivery_type': 'province', 'active': true, 'discount_percent': 0.05,
      'role': 'member', 'requested_role': 'member', 'approval_status': 'approved',
      'email': 'customer$i@example.test', 'is_pinned': false,
      'created_at': '2026-11-21T00:00:00Z', 'published_at': '2026-11-21T00:00:00Z',
      'booking_close_date': '2026-11-25', 'estimated_arrival_date': '2026-11-27',
      'deletion_status': 'active',
    },
  ];
  http.Response reply(http.Request request, dynamic body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, request: request,
          headers: {'content-type': 'application/json'});
  setUpAll(() async {
    expect(SupabaseConfig.isConfigured, isTrue,
        reason: 'Use the CI test-only SUPABASE dart-defines.');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://company-search.invalid', publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false, detectSessionInUri: false),
      httpClient: MockClient((request) async {
        calls.add(request);
        final key = request.url.pathSegments.last;
        if (request.url.path == '/auth/v1/token') {
          final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
          String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
          return reply(request, {
            'access_token': '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': 'search-test', 'exp': exp})}.test',
            'refresh_token': 'test-refresh', 'token_type': 'bearer', 'expires_in': 3600,
            'user': {'id': 'search-test', 'aud': 'authenticated', 'email': 'test@example.test',
              'created_at': '2026-11-21T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}},
          });
        }
        if (key == 'waybill-intake') {
          final body = jsonDecode(request.body) as Map;
          return reply(request, {
            'deliveries': [for (final id in body['delivery_ids'] as List? ?? []) {'id': id, 'customer_code': 'LK 010$id'}],
            'profiles': [for (final id in body['profile_ids'] as List? ?? []) {'id': id, 'customer_code': 'LK 010$id', 'status': 'linked'}],
            'summary': {'mismatch_customers': 0, 'duplicate_customers': 0, 'mismatch_sources': 0},
          });
        }
        if (key == 'list_shipment_filter_batches') {
          return reply(request, [{'route': '한국->라오스 해상', 'shipment_year': 2026, 'voyage': '22'}]);
        }
        if (screens.containsKey(key) || key == 'customer_rate_overrides') {
          if (failLists) return reply(request, {'code': 'TEST_ERROR', 'message': 'Temporary test failure'}, 400);
          final queue = pending[key];
          if (queue != null && queue.isNotEmpty) return reply(request, await queue.removeAt(0).future);
          return reply(request, rows());
        }
        return reply(request, []);
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(email: 'test@example.test', password: 'synthetic-test-only');
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() { calls.clear(); pending.clear(); failLists = false; });

  Future<void> settle(WidgetTester tester) async {
    // functions_client decodes Edge Function JSON outside the fake test clock.
    // Encoding and decoding each cross the isolate boundary. Pump between
    // real event-loop turns so their continuations can schedule the next stage.
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    try {
      await tester.pumpAndSettle();
    } catch (_) {
      // Keep failures actionable without logging synthetic auth headers/tokens.
      debugPrint('HTTP paths: ${calls.map((r) => r.url.path).toList()}');
      rethrow;
    }
  }
  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: screen));
    await settle(tester);
  }
  Finder text(String name) => find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(name));
  Finder searchBar() => find.byType(ManagementFieldSearch);
  Finder input() => find.descendant(of: searchBar(), matching: find.byType(TextField));
  Future<void> submit(WidgetTester tester, String query, {bool enter = false}) async {
    await tester.enterText(input(), query);
    if (enter) {
      await tester.testTextInput.receiveAction(TextInputAction.search);
    } else {
      await tester.tap(find.descendant(of: searchBar(), matching: find.widgetWithText(TextButton, '검색')));
    }
    await settle(tester);
  }
  Future<void> reset(WidgetTester tester) async {
    await tester.tap(find.descendant(of: searchBar(), matching: find.widgetWithText(TextButton, '초기화')));
    await settle(tester);
  }
  for (final entry in screens.entries) {
    testWidgets('${entry.key}: first search, repeated search, reset, no matches and retry', (tester) async {
      await open(tester, entry.value());
      final before = calls.where((r) => r.url.pathSegments.last == entry.key).length;
      await submit(tester, 'Alpha');
      expect(calls.where((r) => r.url.pathSegments.last == entry.key).length, greaterThan(before));
      expect(text('Alpha'), findsWidgets);
      expect(text('Beta'), findsNothing);
      // Typing is a draft until Search or Enter is submitted.
      await tester.enterText(input(), 'Beta');
      await tester.pump();
      expect(text('Alpha'), findsWidgets);
      expect(text('Beta'), findsNothing);
      await submit(tester, 'Beta', enter: true);
      expect(text('Beta'), findsWidgets);
      expect(text('Alpha'), findsNothing);
      await reset(tester);
      expect(text('Alpha'), findsWidgets);
      expect(text('Beta'), findsWidgets);
      expect(tester.widget<TextField>(input()).controller!.text, isEmpty);
      await submit(tester, 'No matching customer');
      expect(text('Alpha'), findsNothing);
      expect(text('Beta'), findsNothing);
      await submit(tester, 'Alpha');
      expect(text('Alpha'), findsWidgets);
      await reset(tester);
      expect(text('Beta'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
    testWidgets('${entry.key}: a slower previous request cannot overwrite the latest list', (tester) async {
      await open(tester, entry.value());
      final older = Completer<dynamic>(), latest = Completer<dynamic>();
      pending[entry.key] = [older, latest];
      // Keep the same real callback as overlapping refresh/search triggers use.
      final onSearch = tester.widget<ManagementFieldSearch>(searchBar()).onChanged;
      onSearch();
      await tester.pump();
      onSearch();
      await tester.pump();
      expect(pending[entry.key], isEmpty);
      latest.complete(rows(['Latest result']));
      await settle(tester);
      expect(text('Latest result'), findsWidgets);
      older.complete(rows(['Outdated result']));
      await settle(tester);
      expect(text('Latest result'), findsWidgets);
      expect(text('Outdated result'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  }
  for (final key in ['local_delivery_profiles', 'admin_list_discount_rules_with_identity', 'shipments']) {
    testWidgets('$key: failure can be retried without reopening the screen', (tester) async {
      await open(tester, screens[key]!());
      failLists = true;
      await submit(tester, 'Alpha');
      expect(searchBar(), findsOneWidget);
      failLists = false;
      await submit(tester, 'Beta');
      expect(text('Beta'), findsWidgets);
      await reset(tester);
      expect(text('Alpha'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  }
}
