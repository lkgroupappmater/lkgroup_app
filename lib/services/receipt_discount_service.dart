import '../config/supabase_config.dart';
import 'supabase_service.dart';

class ReceiptDiscountOverride {
  const ReceiptDiscountOverride({
    this.id,
    required this.routeKey,
    required this.year,
    required this.voyage,
    required this.receiptNumber,
    required this.discountName,
    required this.discountPercent,
  });

  final int? id;
  final String routeKey;
  final int year;
  final String voyage;
  final String receiptNumber;
  final String discountName;
  final double discountPercent;

  factory ReceiptDiscountOverride.fromMap(Map<String, dynamic> row) =>
      ReceiptDiscountOverride(
        id: (row['id'] as num?)?.toInt(),
        routeKey: '${row['route_key'] ?? ''}'.trim(),
        year: (row['shipment_year'] as num?)?.toInt() ?? 0,
        voyage: '${row['voyage'] ?? ''}'.trim(),
        receiptNumber: '${row['receipt_number'] ?? ''}'.trim(),
        discountName: '${row['discount_name'] ?? ''}'.trim(),
        discountPercent:
            double.tryParse('${row['discount_percent'] ?? 0}') ?? 0,
      );
}

class ReceiptDiscountService {
  ReceiptDiscountService._();
  static final instance = ReceiptDiscountService._();

  Future<ReceiptDiscountOverride?> get({
    required String routeKey,
    required int year,
    required String voyage,
    required String receiptNumber,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;
    final raw = await SupabaseService.client.rpc(
      'get_receipt_discount_override',
      params: {
        'p_route_key': routeKey.trim(),
        'p_year': year,
        'p_voyage': voyage.trim(),
        'p_receipt_number': receiptNumber.trim(),
      },
    );
    if (raw is! Map) return null;
    final row = Map<String, dynamic>.from(raw);
    if (row.isEmpty || row['id'] == null) return null;
    return ReceiptDiscountOverride.fromMap(row);
  }

  Future<void> save({
    required String routeKey,
    required int year,
    required String voyage,
    required String receiptNumber,
    required String discountName,
    required double discountPercent,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'save_receipt_discount_override',
      params: {
        'p_route_key': routeKey.trim(),
        'p_year': year,
        'p_voyage': voyage.trim(),
        'p_receipt_number': receiptNumber.trim(),
        'p_discount_name': discountName.trim(),
        'p_discount_percent': discountPercent,
      },
    );
  }

  Future<void> delete({
    required String routeKey,
    required int year,
    required String voyage,
    required String receiptNumber,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'delete_receipt_discount_override',
      params: {
        'p_route_key': routeKey.trim(),
        'p_year': year,
        'p_voyage': voyage.trim(),
        'p_receipt_number': receiptNumber.trim(),
      },
    );
  }
}
