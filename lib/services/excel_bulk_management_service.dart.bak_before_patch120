import '../config/supabase_config.dart';
import 'supabase_service.dart';

class ExcelBulkBatch {
  const ExcelBulkBatch({
    required this.route,
    required this.year,
    required this.voyage,
  });

  final String route;
  final int year;
  final String voyage;

  factory ExcelBulkBatch.fromMap(Map<String, dynamic> map) => ExcelBulkBatch(
        route: '${map['route'] ?? ''}',
        year: (map['shipment_year'] as num?)?.toInt() ?? 0,
        voyage: '${map['voyage'] ?? ''}',
      );
}

class ExcelBulkManagementService {
  ExcelBulkManagementService._();
  static final instance = ExcelBulkManagementService._();

  Future<List<ExcelBulkBatch>> listBatches() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw =
        await SupabaseService.client.rpc('admin_excel_bulk_batches') as List;
    return raw
        .map((e) => ExcelBulkBatch.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listRows({
    required String route,
    required int year,
    required String voyage,
  }) async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw = await SupabaseService.client.rpc(
      'admin_excel_bulk_rows',
      params: {
        'p_route': route,
        'p_year': year,
        'p_voyage': voyage,
      },
    ) as List;
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<void> setLocked(List<String> ids, bool locked) async {
    if (!SupabaseConfig.isConfigured || ids.isEmpty) return;
    final numeric = ids.map(int.tryParse).whereType<int>().toList();
    if (numeric.isEmpty) return;
    await SupabaseService.client.rpc(
      'admin_excel_bulk_set_lock',
      params: {'p_ids': numeric, 'p_locked': locked},
    );
  }

  Future<void> updateRow({
    required String id,
    required String boxNumber,
    required String name,
    required String phone,
    required String receiptNumber,
    required String unloadingZone,
    required String notes,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final numericId = int.tryParse(id);
    if (numericId == null) return;
    await SupabaseService.client.rpc(
      'admin_excel_bulk_update',
      params: {
        'p_shipment_id': numericId,
        'p_box_number': boxNumber.trim(),
        'p_consignee_name': name.trim(),
        'p_consignee_phone': phone.trim(),
        'p_receipt_number': receiptNumber.trim(),
        'p_unloading_zone': unloadingZone.trim(),
        'p_notes': notes.trim(),
      },
    );
  }
}
