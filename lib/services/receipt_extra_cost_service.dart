import '../config/supabase_config.dart';
import 'supabase_service.dart';

class ExtraCostItem {
  const ExtraCostItem({
    this.id,
    required this.name,
    required this.amountUsd,
    this.discountApplies = false,
    this.deliveryType,
    this.pending = false,
  });

  final int? id;
  final String name;
  final double amountUsd;
  final bool discountApplies;
  final String? deliveryType;
  final bool pending;

  factory ExtraCostItem.fromMap(Map<String, dynamic> row) => ExtraCostItem(
    id: (row['id'] as num?)?.toInt(),
    name: '${row['cost_name'] ?? row['name'] ?? ''}'.trim(),
    amountUsd:
        double.tryParse('${row['amount_usd'] ?? row['amount'] ?? 0}') ?? 0,
    discountApplies: row['discount_applies'] == true,
    deliveryType: row['delivery_type'] as String?,
  );
}

class ReceiptExtraCostService {
  ReceiptExtraCostService._();
  static final instance = ReceiptExtraCostService._();

  Future<List<ExtraCostItem>> list({
    required String route,
    required int year,
    required String voyage,
    required String receiptNumber,
  }) async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw = await SupabaseService.client.rpc(
      'list_receipt_extra_costs_v2',
      params: {
        'p_route': route.trim(),
        'p_year': year,
        'p_voyage': voyage.trim(),
        'p_receipt_number': receiptNumber.trim(),
      },
    );
    return List<Map<String, dynamic>>.from(raw as List)
        .map(ExtraCostItem.fromMap)
        .toList(growable: false);
  }

  Future<void> save({
    int? id,
    required String route,
    required int year,
    required String voyage,
    required String receiptNumber,
    required String name,
    required double amountUsd,
    bool discountApplies = false,
    String? deliveryType,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'save_receipt_extra_cost_v2',
      params: {
        'p_id': id,
        'p_route': route.trim(),
        'p_year': year,
        'p_voyage': voyage.trim(),
        'p_receipt_number': receiptNumber.trim(),
        'p_cost_name': name.trim(),
        'p_amount_usd': amountUsd,
        'p_discount_applies': discountApplies,
        'p_delivery_type': deliveryType,
      },
    );
  }

  Future<void> delete(int id) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'delete_receipt_extra_cost',
      params: {'p_id': id},
    );
  }
}
