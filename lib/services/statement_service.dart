import '../config/supabase_config.dart';
import 'customer_benefit_service.dart';
import 'supabase_service.dart';

class StatementService {
  StatementService._();
  static final instance = StatementService._();

  /// Uses the same authorized receipt context as the website. Identities are
  /// resolved by the server; this client never requests the full delivery list.
  Future<LocalDeliveryRule?> deliveryForReceipt({
    required String route,
    required int year,
    required String voyage,
    required String receiptNumber,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (!SupabaseConfig.isConfigured || rows.isEmpty) return null;
    final raw = await SupabaseService.client.rpc(
      'statement_delivery_context',
      params: {
        'p_route': route,
        'p_year': year,
        'p_voyage': voyage,
        'p_receipt_number': receiptNumber,
      },
    );
    final context = Map<String, dynamic>.from(raw as Map);
    final matches = (context['matches'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map)).toList();
    final deliveries = (context['deliveries'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map)).toList();
    final appearance = Map<String, dynamic>.from(
      context['appearance'] as Map? ?? const {},
    );
    for (final row in rows) {
      for (final match in matches) {
        if (match['id'] == null ||
            match['name'] != '${row['consignee_name'] ?? ''}' ||
            match['phone'] != '${row['consignee_phone'] ?? ''}') continue;
        for (final profile in deliveries) {
          if (profile['active'] != true ||
              '${profile['id']}' != '${match['id']}') continue;
          final rule = LocalDeliveryRule.fromMap(profile);
          final category = rule.deliveryType + (rule.isPrepaid ? '_prepaid' : '');
          return LocalDeliveryRule.fromMap({
            ...profile,
            'display_color': appearance[category],
          });
        }
      }
    }
    return null;
  }

  Future<String?> arrivalDate({
    required String route,
    required int year,
    required String voyage,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;
    final value = await SupabaseService.client.rpc(
      'statement_arrival_date',
      params: {
        'p_route': route,
        'p_year': year,
        'p_voyage': voyage,
      },
    );
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  Future<List<Map<String, dynamic>>> rowsForReceipt({
    required String route,
    required int year,
    required String voyage,
    required String receiptNumber,
  }) async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw = await SupabaseService.client.rpc(
      'statement_rows_for_receipt',
      params: {
        'p_route': route,
        'p_year': year,
        'p_voyage': voyage,
        'p_receipt_number': receiptNumber,
      },
    ) as List;
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }
}

