import '../config/supabase_config.dart';
import 'supabase_service.dart';
import '../core/route_catalog.dart';
import 'document_tax_service.dart';

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
    final rows = raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    if (rows.isNotEmpty) {
      final tax = await DocumentTaxService.forRemark(RouteCatalog.keyFor(route),
          '${rows.first['special_note_auto'] ?? ''}');
      for (final row in rows) {
        row['document_vat_rate'] = tax.rate;
        row['document_vat_applicable'] = tax.applicable;
      }
    }
    return rows;
  }
}
