import '../config/supabase_config.dart';
import 'supabase_service.dart';

class ManagementMenuStatus {
  const ManagementMenuStatus({
    required this.pendingCount,
    this.activityType,
  });

  final int pendingCount;
  final String? activityType;
}

class AdminManagementStatusService {
  AdminManagementStatusService._();
  static final instance = AdminManagementStatusService._();

  Future<Map<String, ManagementMenuStatus>> fetch() async {
    if (!SupabaseConfig.isConfigured) return const {};
    try {
      final raw =
          await SupabaseService.client.rpc('admin_management_menu_status') as List;
      final result = <String, ManagementMenuStatus>{};
      for (final item in raw) {
        final row = Map<String, dynamic>.from(item as Map);
        final key = '${row['menu_key'] ?? ''}';
        if (key.isEmpty) continue;
        result[key] = ManagementMenuStatus(
          pendingCount: (row['pending_count'] as num?)?.toInt() ?? 0,
          activityType: '${row['activity_type'] ?? ''}'.trim().isEmpty
              ? null
              : '${row['activity_type']}',
        );
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> markSeen(String menuKey) async {
    if (!SupabaseConfig.isConfigured || menuKey.isEmpty) return;
    try {
      await SupabaseService.client.rpc(
        'admin_mark_management_menu_seen',
        params: {'p_menu_key': menuKey},
      );
    } catch (_) {
      // badge 기능 실패가 기존 메뉴 진입을 막지 않음
    }
  }
}
