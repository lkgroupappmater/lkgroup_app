import 'supabase_service.dart';

abstract final class SupabaseConnectionService {
  static bool get isConfigured => SupabaseService.isReady;

  static Future<List<Map<String, dynamic>>> testConnection() async {
    final rows = await SupabaseService.client
        .from('shipments')
        .select('shipment_no, consignee_name, status')
        .limit(5);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<bool> ping() async {
    await SupabaseService.client.from('shipments').select('id').limit(1);
    return true;
  }
}
