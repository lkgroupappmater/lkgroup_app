import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Supabase-backed schedules and notices.
/// RLS remains the final authority; UI checks are only for presentation.
class ContentService {
  ContentService._();

  static SupabaseClient? get _client => SupabaseConfig.isConfigured
      ? Supabase.instance.client
      : null;

  static Future<List<Map<String, dynamic>>> fetchSchedules({
    bool includePendingDeletion = false,
  }) async {
    final client = _client;
    if (client == null) return <Map<String, dynamic>>[];
    var query = client.from('shipping_schedules').select();
    if (!includePendingDeletion) query = query.isFilter('deleted_at', null);
    final rows = await query.order('departure_date', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> fetchNotices({
    bool includePendingDeletion = false,
  }) async {
    final client = _client;
    if (client == null) return <Map<String, dynamic>>[];
    var query = client.from('notices').select();
    if (!includePendingDeletion) query = query.isFilter('deleted_at', null);
    final rows = await query.order('is_pinned', ascending: false).order('published_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<Map<String, dynamic>> createSchedule(Map<String, dynamic> data) async {
    final client = _client;
    if (client == null) throw StateError('Supabase가 초기화되지 않았습니다.');
    final row = await client.from('shipping_schedules').insert(data).select().single();
    return Map<String, dynamic>.from(row);
  }

  static Future<Map<String, dynamic>> updateSchedule(String id, Map<String, dynamic> data) async {
    final client = _client;
    if (client == null) throw StateError('Supabase가 초기화되지 않았습니다.');
    final row = await client.from('shipping_schedules').update(data).eq('id', id).select().single();
    return Map<String, dynamic>.from(row);
  }

  static Future<void> requestScheduleDeletion(String id) async {
    final client = _client;
    if (client == null) throw StateError('Supabase가 초기화되지 않았습니다.');
    await client.from('shipping_schedules').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'purge_after': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      'deletion_status': 'pending',
    }).eq('id', id);
  }

  static Future<Map<String, dynamic>> createNotice(Map<String, dynamic> data) async {
    final client = _client;
    if (client == null) throw StateError('Supabase가 초기화되지 않았습니다.');
    final row = await client.from('notices').insert(data).select().single();
    return Map<String, dynamic>.from(row);
  }

  static Future<Map<String, dynamic>> updateNotice(String id, Map<String, dynamic> data) async {
    final client = _client;
    if (client == null) throw StateError('Supabase가 초기화되지 않았습니다.');
    final row = await client.from('notices').update(data).eq('id', id).select().single();
    return Map<String, dynamic>.from(row);
  }

  static Future<void> requestNoticeDeletion(String id) async {
    final client = _client;
    if (client == null) throw StateError('Supabase가 초기화되지 않았습니다.');
    await client.from('notices').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'purge_after': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      'deletion_status': 'pending',
    }).eq('id', id);
  }
}

