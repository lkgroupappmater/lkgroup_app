import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lkgroup_app/config/supabase_config.dart';
import 'package:lkgroup_app/services/statement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <http.Request>[];
  var status = 200;
  var response = <String, dynamic>{};
  final rows = <Map<String, dynamic>>[
    {'consignee_name': '고객 A', 'consignee_phone': '02012345678'},
    {'consignee_name': '고객 B', 'consignee_phone': '02087654321'},
  ];
  final service = StatementService.instance;
  Future<dynamic> load([List<Map<String, dynamic>>? source]) =>
      service.deliveryForReceipt(route: '한국->라오스 해상', year: 2026,
          voyage: '010', receiptNumber: 'LKS 0120', rows: source ?? rows);
  Map<String, dynamic> delivery(int id, String type, String paidBy) => {
    'id': id, 'active': true, 'customer_name': '고객 $id',
    'phone': '02012345678', 'delivery_type': type, 'paid_by': paidBy,
    'local_company': '운송사', 'destination_address': '배송지',
  };

  setUpAll(() async {
    expect(SupabaseConfig.isConfigured, isTrue,
        reason: 'Run with the CI test-only SUPABASE dart-defines.');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://company-search.invalid', publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request);
        return http.Response(jsonEncode(response), status, request: request,
            headers: {'content-type': 'application/json'});
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() {
    calls.clear(); status = 200;
    response = {
      'matches': [
        {'name': '고객 B', 'phone': '02087654321', 'id': 2},
        {'name': '고객 A', 'phone': '02012345678', 'id': 1},
      ],
      'deliveries': [delivery(2, 'province', ''), delivery(1, 'city', '선결재')],
      'appearance': {'city_prepaid': 'A1B2C3'},
    };
  });
  test('only receipt identifiers are sent to the common authorized RPC', () async {
    final rule = await load();
    expect(rule.id, 1);
    expect(calls.single.url.path, '/rest/v1/rpc/statement_delivery_context');
    expect(jsonDecode(calls.single.body), {
      'p_route': '한국->라오스 해상', 'p_year': 2026,
      'p_voyage': '010', 'p_receipt_number': 'LKS 0120',
    });
  });
  test('server selection follows receipt row order and scoped prepaid color', () async {
    final rule = await load();
    expect(rule.id, 1);
    expect(rule.deliveryType, 'city');
    expect(rule.isPrepaid, isTrue);
    expect(rule.displayColor, 'A1B2C3');
    expect(rule.destinationAddress, '배송지');
  });
  test('unmatched or inactive profiles are never substituted by name or phone', () async {
    response['deliveries'] = [
      {...delivery(1, 'city', ''), 'active': false}, delivery(99, 'province', ''),
    ];
    expect(await load(), isNull);
  });
  test('no authorized rows skip delivery lookup', () async {
    expect(await load([]), isNull);
    expect(calls, isEmpty);
  });
  test('empty authorized server context stays empty', () async {
    response = {'matches': [], 'deliveries': [], 'appearance': {}};
    expect(await load(), isNull);
    expect(calls, hasLength(1));
  });
  test('permission errors propagate without a broad-table fallback', () async {
    status = 403;
    response = {'code': '42501', 'message': 'not authorized', 'details': null, 'hint': null};
    await expectLater(load(), throwsA(isA<PostgrestException>()));
    expect(calls, hasLength(1));
  });
  test('a profile for a different identity cannot be selected', () async {
    expect(await load([{'consignee_name': '타인', 'consignee_phone': '02012345678'}]), isNull);
  });
}
