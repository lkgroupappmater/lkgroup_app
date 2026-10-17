import '../config/supabase_config.dart';
import 'receipt_settlement_service.dart';
import 'supabase_service.dart';

class SettlementSnapshotService {
  SettlementSnapshotService._();
  static final instance = SettlementSnapshotService._();

  /// Read only the compact saved totals; opening the menu never recalculates cargo.
  Future<List<Map<String, dynamic>>> listSummaries() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = <Map<String, dynamic>>[];
    while (true) {
      final page = await SupabaseService.client
          .from('voyage_settlement_snapshots')
          .select('id,route_key,route_label,shipment_year,voyage,total_quantity,gross_usd,discount_usd,net_usd,calculated_at')
          .order('calculated_at', ascending: false)
          .order('id')
          .range(rows.length, rows.length + 499);
      rows.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < 500) return rows;
    }
  }

  Future<void> save({
    required String routeKey,
    required String routeLabel,
    required int year,
    required String voyage,
    required VoyageSettlement settlement,
  }) async {
    if (!SupabaseConfig.isConfigured) return;

    final receipts = settlement.receipts.map((r) => {
      'receipt_number': r.receiptNumber,
      'customer_name': r.customerName,
      'phone': r.phone,
      'total_quantity': r.totalQuantity,
      'gross_usd': r.grossUsd,
      'discount_usd': r.discountUsd,
      'net_usd': r.netUsd,
      'discount_by_group': r.freight.discountByGroup,
      'lines': r.freight.lines.map((line) => {
        'shipment_id': line.shipmentId,
        'box_number': line.boxNumber,
        'invoice_number': line.invoiceNumber,
        'gross_usd': line.grossAmountUsd,
        'discount_percent': line.discountPercent,
        'discount_usd': line.discountAmountUsd,
        'net_usd': line.amountUsd,
        'discount_group': line.discountGroup,
        'discount_customer': line.discountCustomer,
        'combined_quantity': line.discountCombinedQuantity,
      }).toList(growable: false),
    }).toList(growable: false);

    await SupabaseService.client.rpc(
      'admin_save_voyage_settlement_snapshot',
      params: {
        'p_route_key': routeKey,
        'p_route_label': routeLabel,
        'p_year': year,
        'p_voyage': voyage,
        'p_total_quantity': settlement.totalQuantity,
        'p_gross_usd': settlement.grossUsd,
        'p_discount_usd': settlement.discountUsd,
        'p_net_usd': settlement.netUsd,
        'p_discount_by_group': settlement.discountByGroup,
        'p_receipts': receipts,
      },
    );
  }
}
