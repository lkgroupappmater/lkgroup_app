import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/app_language.dart';
import 'ai_assistant_service.dart';

class ContentService {
  ContentService._();

  static bool _backfillAttempted = false;

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
    AppLanguage language = AppLanguage.korean,
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

    return _localizedRows(
      result,
      language,
      const <String>['route', 'origin', 'destination', 'status', 'detail'],
    );
  }

  static Future<List<Map<String, dynamic>>> fetchNotices({
    bool includePendingDeletion = false,
    AppLanguage language = AppLanguage.korean,
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

    return _localizedRows(
      result,
      language,
      const <String>['title', 'content'],
    );
  }

  static Future<Map<String, dynamic>> createSchedule(
      Map<String, dynamic> data) async {
    final client = _requireClient();
    final translated = await _withTranslations(
      data,
      const <String>['route', 'origin', 'destination', 'status', 'detail'],
    );
    final row = await client
        .from('shipping_schedules')
        .insert({
          ...translated,
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
    final translated = await _withTranslations(
      data,
      const <String>['route', 'origin', 'destination', 'status', 'detail'],
    );
    final row = await client
        .from('shipping_schedules')
        .update(translated)
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
    final translated = await _withTranslations(
      data,
      const <String>['title', 'content'],
    );
    final row = await client
        .from('notices')
        .insert({
          ...translated,
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
    final translated = await _withTranslations(
      data,
      const <String>['title', 'content'],
    );
    final row = await client
        .from('notices')
        .update(translated)
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

  /// Generates stored English/Lao text for legacy rows once an authorized
  /// manager opens the home screen. Public readers then use the stored columns
  /// and never call the paid AI endpoint directly.
  static Future<void> backfillMissingTranslations() async {
    if (_backfillAttempted) return;
    _backfillAttempted = true;
    final client = _requireClient();
    try {
      final notices = List<Map<String, dynamic>>.from(
        await client.from('notices').select(),
      );
      for (final row in notices) {
        const fields = <String>['title', 'content'];
        if (!_needsTranslation(row, fields)) continue;
        final translated = await _withTranslations(row, fields);
        final values = _translationValues(translated, fields);
        if (values.length == fields.length * 2) {
          await client.from('notices').update(values).eq('id', row['id']);
        }
      }

      final schedules = List<Map<String, dynamic>>.from(
        await client.from('shipping_schedules').select(),
      );
      for (final row in schedules) {
        const fields = <String>[
          'route',
          'origin',
          'destination',
          'status',
          'detail',
        ];
        if (!_needsTranslation(row, fields)) continue;
        final translated = await _withTranslations(row, fields);
        final values = _translationValues(translated, fields);
        if (values.length == fields.length * 2) {
          await client
              .from('shipping_schedules')
              .update(values)
              .eq('id', row['id']);
        }
      }
    } catch (_) {
      // Backfill is optional and must not interrupt the public home screen.
    }
  }

  static SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase가 초기화되지 않았습니다.');
    }
    return client;
  }

  static List<Map<String, dynamic>> _localizedRows(
    List<Map<String, dynamic>> rows,
    AppLanguage language,
    List<String> fields,
  ) {
    if (language == AppLanguage.korean) return rows;
    final suffix = language == AppLanguage.lao ? 'lo' : 'en';
    return [
      for (final row in rows)
        <String, dynamic>{
          ...row,
          for (final field in fields)
            field: '${row['${field}_$suffix'] ?? ''}'.trim().isEmpty
                ? row[field]
                : row['${field}_$suffix'],
        },
    ];
  }

  static Future<Map<String, dynamic>> _withTranslations(
    Map<String, dynamic> data,
    List<String> fields,
  ) async {
    final result = Map<String, dynamic>.from(data);
    final source = [for (final field in fields) '${data[field] ?? ''}'];
    try {
      final english = await AiAssistantService.translate(
        source,
        AppLanguage.english,
      );
      final lao = await AiAssistantService.translate(source, AppLanguage.lao);
      for (var index = 0; index < fields.length; index++) {
        result['${fields[index]}_en'] = english[index];
        result['${fields[index]}_lo'] = lao[index];
      }
    } catch (_) {
      // Content saving remains available when the AI provider is unavailable.
      // Existing stored translations remain untouched on partial updates.
    }
    return result;
  }

  static bool _needsTranslation(
    Map<String, dynamic> row,
    List<String> fields,
  ) =>
      fields.any(
        (field) =>
            '${row['${field}_en'] ?? ''}'.trim().isEmpty ||
            '${row['${field}_lo'] ?? ''}'.trim().isEmpty,
      );

  static Map<String, dynamic> _translationValues(
    Map<String, dynamic> row,
    List<String> fields,
  ) =>
      <String, dynamic>{
        for (final field in fields)
          if (row.containsKey('${field}_en')) '${field}_en': row['${field}_en'],
        for (final field in fields)
          if (row.containsKey('${field}_lo')) '${field}_lo': row['${field}_lo'],
      };
}
