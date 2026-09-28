import 'supabase_service.dart';

class CompanyVerificationService {
  static Future<List<Map<String, dynamic>>> list([String status = 'pending']) async {
    final raw = await SupabaseService.client.rpc('admin_list_company_verifications', params: {'p_status': status});
    return (raw as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }
  static Future<Map<String, dynamic>> mine() async => Map<String, dynamic>.from(
      await SupabaseService.client.rpc('my_company_verification') as Map);
  static Future<void> review(int id, String action) async {
    await SupabaseService.client.rpc('admin_review_company_verification', params: {'p_request_id': id, 'p_action': action});
  }
}
