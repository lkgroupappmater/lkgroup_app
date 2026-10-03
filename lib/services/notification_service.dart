import '../config/supabase_config.dart';
import 'supabase_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  Future<List<Map<String, dynamic>>> fetchUnread() async {
    if (!SupabaseConfig.isConfigured ||
        SupabaseService.client.auth.currentUser == null) {
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
    if (!SupabaseConfig.isConfigured ||
        SupabaseService.client.auth.currentUser == null) {
      return const [];
    }

    // 읽지 않은 알림은 기간 제한 없이 계속 보관해서 표시합니다.
    // 이미 확인한 알림은 read_at 기준 24시간까지만 알림 목록에 표시합니다.
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .toIso8601String();

    final rows = await SupabaseService.client
        .from('user_notifications')
        .select()
        .or('is_read.eq.false,read_at.gte.$cutoff')
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> feed({int offset = 0}) async {
    if (!SupabaseConfig.isConfigured ||
        SupabaseService.client.auth.currentUser == null)
      return {'rows': <Map<String, dynamic>>[], 'unread_count': 0};
    return Map<String, dynamic>.from(await SupabaseService.client
        .rpc('list_my_notification_feed', params: {'p_offset': offset}) as Map);
  }

  Future<void> read(int id) async => SupabaseService.client
      .rpc('read_my_notification', params: {'p_notification_id': id});
  Future<Map<String, dynamic>?> relatedRequest(int id) async {
    final data = await SupabaseService.client
        .rpc('get_my_notification_request', params: {'p_notification_id': id});
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }
}
