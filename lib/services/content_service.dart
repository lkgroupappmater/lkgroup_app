import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class ContentService {
  ContentService._();

  static SupabaseClient? get _client =>
      SupabaseConfig.isConfigured ? Supabase.instance.client : null;

  static Future<void> purgeExpiredContent() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('purge_expired_content');
    } catch (_) {
      // 마이그레이션 적용 전에도 조회 자체는 계속 동작하도록 합니다.
    }
  }

  static Future<List<Map<String, dynamic>>> fetchSchedules({
    bool includePendingDeletion = false,
  }) async {
    final client = _client;
    if (client == null) return <Map<String, dynamic>>[];

    await purgeExpiredContent();

    var query = client.from('shipping_schedules').select();
    if (!includePendingDeletion) {
      query = query
          .isFilter('deleted_at', null)
          .eq('deletion_status', 'active');
    }

    final rows = await query;
    var result = List<Map<String, dynamic>>.from(rows);

    // 홈용 조회에서는 DB/RLS 상태와 무관하게 앱에서도 한 번 더
    // active + 미삭제 자료만 통과시킵니다.
    if (!includePendingDeletion) {
      result = result.where((row) {
        final deletionStatus =
            '${row['deletion_status'] ?? 'active'}'.trim().toLowerCase();
        final deletedAt = row['deleted_at'];
        return deletionStatus == 'active' &&
            (deletedAt == null || '$deletedAt'.trim().isEmpty);
      }).toList();
    }

    result.sort((a, b) {
      final left = (a['departure_date'] ??
              a['booking_close_date'] ??
              a['closing_date'] ??
              '')
          .toString();
      final right = (b['departure_date'] ??
              b['booking_close_date'] ??
              b['closing_date'] ??
              '')
          .toString();
      return left.compareTo(right);
    });

    return result;
  }

  static Future<List<Map<String, dynamic>>> fetchNotices({
    bool includePendingDeletion = false,
  }) async {
    final client = _client;
    if (client == null) return <Map<String, dynamic>>[];

    await purgeExpiredContent();

    var query = client.from('notices').select();
    if (!includePendingDeletion) {
      query = query
          .isFilter('deleted_at', null)
          .eq('deletion_status', 'active');
    }

    final rows = await query
        .order('is_pinned', ascending: false)
        .order('published_at', ascending: false);

    var result = List<Map<String, dynamic>>.from(rows);

    if (!includePendingDeletion) {
      result = result.where((row) {
        final deletionStatus =
            '${row['deletion_status'] ?? 'active'}'.trim().toLowerCase();
        final deletedAt = row['deleted_at'];
        return deletionStatus == 'active' &&
            (deletedAt == null || '$deletedAt'.trim().isEmpty);
      }).toList();
    }

    return result;
  }

  static Future<Map<String, dynamic>> createSchedule(
      Map<String, dynamic> data) async {
    final client = _requireClient();
    final row = await client
        .from('shipping_schedules')
        .insert({
          ...data,
          'deletion_status': 'active',
          'deleted_at': null,
          'purge_after': null,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  static Future<Map<String, dynamic>> updateSchedule(
    String id,
    Map<String, dynamic> data,
  ) async {
    final client = _requireClient();
    final row = await client
        .from('shipping_schedules')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  static Future<void> requestScheduleDeletion(String id) async {
    final client = _requireClient();
    final now = DateTime.now().toUtc();
    await client.from('shipping_schedules').update({
      'deleted_at': now.toIso8601String(),
      'purge_after': now.add(const Duration(days: 30)).toIso8601String(),
      'deletion_status': 'pending',
    }).eq('id', id);
  }

  static Future<void> restoreSchedule(String id) async {
    final client = _requireClient();
    await client.from('shipping_schedules').update({
      'deleted_at': null,
      'purge_after': null,
      'deletion_status': 'active',
    }).eq('id', id);
  }

  static Future<void> hardDeleteSchedule(String id) async {
    final client = _requireClient();
    await client.from('shipping_schedules').delete().eq('id', id);
  }

  static Future<Map<String, dynamic>> createNotice(
      Map<String, dynamic> data) async {
    final client = _requireClient();
    final row = await client
        .from('notices')
        .insert({
          ...data,
          'deletion_status': 'active',
          'deleted_at': null,
          'purge_after': null,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  static Future<Map<String, dynamic>> updateNotice(
    String id,
    Map<String, dynamic> data,
  ) async {
    final client = _requireClient();
    final row = await client
        .from('notices')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  static Future<void> requestNoticeDeletion(String id) async {
    final client = _requireClient();
    final now = DateTime.now().toUtc();
    await client.from('notices').update({
      'deleted_at': now.toIso8601String(),
      'purge_after': now.add(const Duration(days: 30)).toIso8601String(),
      'deletion_status': 'pending',
    }).eq('id', id);
  }

  static Future<void> restoreNotice(String id) async {
    final client = _requireClient();
    await client.from('notices').update({
      'deleted_at': null,
      'purge_after': null,
      'deletion_status': 'active',
    }).eq('id', id);
  }

  static Future<void> hardDeleteNotice(String id) async {
    final client = _requireClient();
    await client.from('notices').delete().eq('id', id);
  }

  static SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase가 초기화되지 않았습니다.');
    }
    return client;
  }
}
