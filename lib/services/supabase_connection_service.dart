import 'package:supabase_flutter/supabase_flutter.dart';

/// Small Supabase access layer used by the app.
///
/// Keep database queries in service classes rather than directly in widgets.
/// This makes it easier to replace mock data with Supabase data incrementally.
abstract final class SupabaseConnectionService {
  static SupabaseClient get client => Supabase.instance.client;

  /// Confirms that the app can reach the `shipments` table.
  ///
  /// The table must exist in Supabase. RLS policies must allow the current
  /// request to read rows, otherwise Supabase returns an error.
  static Future<List<Map<String, dynamic>>> testConnection() async {
    final result = await client
        .from('shipments')
        .select('shipment_no, consignee_name, status')
        .limit(5);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Reads recent shipment rows for the shipment-search screen.
  /// TODO: Add route/category and recipient filters after the Excel schema is
  /// finalized.
  static Future<List<Map<String, dynamic>>> fetchShipments() async {
    final result = await client
        .from('shipments')
        .select()
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(result);
  }
}
