import '../config/supabase_config.dart';
import 'supabase_service.dart';

class QuoteService {
  QuoteService._();
  static final instance = QuoteService._();

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    if (!SupabaseConfig.isConfigured) {
      return {'id': DateTime.now().microsecondsSinceEpoch, 'status': 'pending', ...data};
    }
    final row = await SupabaseService.client.from('quote_requests').insert(data).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> listMine() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client.from('quote_requests').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listForAdmin() => listMine();

  Future<void> updateStatus(int id, String status, {String? note, num? amount}) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('quote_requests').update({
      'status': status, if (note != null) 'admin_note': note, if (amount != null) 'quoted_amount': amount,
    }).eq('id', id);
  }
}
