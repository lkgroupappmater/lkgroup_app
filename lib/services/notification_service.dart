import '../config/supabase_config.dart';
import 'supabase_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  Future<List<Map<String, dynamic>>> fetchUnread() async {
    if (!SupabaseConfig.isConfigured || SupabaseService.client.auth.currentUser == null) {
      return const [];
    }
    final rows = await SupabaseService.client
        .from('user_notifications')
        .select()
        .eq('is_read', false)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> fetchRecent() async {
    if (!SupabaseConfig.isConfigured || SupabaseService.client.auth.currentUser == null) {
      return const [];
    }
    final rows = await SupabaseService.client
        .from('user_notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> markAllRead() async {
    final user = SupabaseService.client.auth.currentUser;
    if (!SupabaseConfig.isConfigured || user == null) return;
    await SupabaseService.client
        .from('user_notifications')
        .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
        .eq('user_id', user.id)
        .eq('is_read', false);
  }
}
