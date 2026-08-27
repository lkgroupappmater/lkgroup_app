import '../config/supabase_config.dart';
import 'supabase_service.dart';

class ProfileService {
  ProfileService._();
  static final instance = ProfileService._();

  Future<List<Map<String, dynamic>>> listPendingMembers() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client.from('profiles').select().eq('approval_status', 'pending').eq('role', 'member');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> approveMember(String userId) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('profiles').update({'approval_status': 'approved'}).eq('id', userId);
  }

  Future<void> rejectMember(String userId) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('profiles').update({'approval_status': 'rejected'}).eq('id', userId);
  }

  Future<List<Map<String, dynamic>>> listProvisionRequests() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client.from('account_provision_requests').select().eq('status', 'pending').order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> reviewProvisionRequest(int id, String status) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('account_provision_requests').update({
      'status': status, 'reviewed_by': SupabaseService.client.auth.currentUser?.id, 'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }
}
