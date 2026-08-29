import '../config/supabase_config.dart';
import 'supabase_service.dart';

class StatementService {
  StatementService._();
  static final instance = StatementService._();

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
