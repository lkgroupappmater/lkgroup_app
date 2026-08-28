import '../config/supabase_config.dart';
import 'supabase_service.dart';

class QuoteService {
  QuoteService._();
  static final instance = QuoteService._();

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    if (!SupabaseConfig.isConfigured) {
      return {
        'id': DateTime.now().microsecondsSinceEpoch,
        'status': 'pending',
        ...data,
      };
    }
    final row = await SupabaseService.client
        .from('quote_requests')
        .insert(data)
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> listMine() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client
        .from('quote_requests')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listForAdmin() => listMine();

  Future<void> updateStatus(int id, String status,
      {String? note, num? amount}) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('quote_requests').update({
      'status': status,
      if (note != null) 'admin_note': note,
      if (amount != null) 'quoted_amount': amount,
    }).eq('id', id);
  }

  Future<void> createSpecialQuote({
    required String route,
    required String subject,
    required String content,
    required String otherContact,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'create_special_quote_request',
      params: {
        'p_route': route,
        'p_subject': subject,
        'p_content': content,
        'p_other_contact': otherContact,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listMySpecialQuotes() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client.rpc('list_my_special_quotes');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> listAdminSpecialQuotes() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client.rpc('list_admin_special_quotes');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> updateSpecialQuote({
    required int quoteId,
    required String route,
    required String subject,
    required String content,
    required String otherContact,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'update_special_quote_request',
      params: {
        'p_quote_id': quoteId,
        'p_route': route,
        'p_subject': subject,
        'p_content': content,
        'p_other_contact': otherContact,
      },
    );
  }

  Future<void> addSpecialQuoteMessage({
    required int quoteId,
    required String message,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'add_special_quote_message',
      params: {'p_quote_id': quoteId, 'p_message': message},
    );
  }

  Future<void> updateAdminReply({
    required int messageId,
    required String message,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'update_special_quote_admin_reply',
      params: {'p_message_id': messageId, 'p_message': message},
    );
  }

  Future<void> deleteAdminReply(int messageId) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'delete_special_quote_admin_reply',
      params: {'p_message_id': messageId},
    );
  }

  Future<void> requestDelete(int quoteId) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'request_special_quote_delete',
      params: {'p_quote_id': quoteId},
    );
  }

  Future<void> cancelDelete(int quoteId) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'cancel_special_quote_delete',
      params: {'p_quote_id': quoteId},
    );
  }

  Future<void> deleteNow(int quoteId) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'hide_special_quote_now',
      params: {'p_quote_id': quoteId},
    );
  }
}
