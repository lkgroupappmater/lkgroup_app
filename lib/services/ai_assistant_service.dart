import '../core/app_language.dart';
import 'supabase_service.dart';

/// Thin client for the authenticated Supabase `ai-assistant` Edge Function.
///
/// Fixed UI labels remain bundled in the app. Only administrator-authored
/// content and consultation questions are sent for AI processing.
class AiAssistantService {
  AiAssistantService._();

  static final Map<String, String> _translationCache = <String, String>{};

  static Future<List<String>> translate(
    List<String> texts,
    AppLanguage language,
  ) async {
    if (language == AppLanguage.korean || texts.isEmpty) {
      return List<String>.from(texts);
    }

    final output = List<String>.from(texts);
    final missingTexts = <String>[];
    final missingIndexes = <int>[];

    for (var i = 0; i < texts.length; i++) {
      final source = texts[i].trim();
      if (source.isEmpty) continue;
      final cacheKey = '${language.code}\u0000$source';
      final cached = _translationCache[cacheKey];
      if (cached != null) {
        output[i] = cached;
      } else {
        missingTexts.add(source);
        missingIndexes.add(i);
      }
    }

    // The Edge Function accepts up to 30 items per request.
    for (var start = 0; start < missingTexts.length; start += 30) {
      final end = (start + 30 < missingTexts.length)
          ? start + 30
          : missingTexts.length;
      final chunk = missingTexts.sublist(start, end);
      final response = await SupabaseService.client.functions.invoke(
        'ai-assistant',
        body: <String, dynamic>{
          'mode': 'translate',
          'target_language': language.code,
          'texts': chunk,
        },
      );
      if (response.status < 200 || response.status >= 300) {
        throw StateError('AI translation failed (${response.status})');
      }
      final body = response.data;
      final translated = body is Map && body['translations'] is List
          ? List<dynamic>.from(body['translations'] as List)
          : const <dynamic>[];
      if (translated.length != chunk.length) {
        throw StateError(
          'AI translation returned ${translated.length} items for '
          '${chunk.length} inputs.',
        );
      }
      for (var offset = 0; offset < chunk.length; offset++) {
        final value = '${translated[offset]}'.trim();
        final safeValue = value.isEmpty ? chunk[offset] : value;
        final originalIndex = missingIndexes[start + offset];
        output[originalIndex] = safeValue;
        _translationCache['${language.code}\u0000${chunk[offset]}'] = safeValue;
      }
    }
    return output;
  }

  static Future<List<Map<String, dynamic>>> history() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return [];
    final rows = await SupabaseService.client.from('ai_consultations')
        .select('id,question,answer,language,sources,created_at')
        .eq('user_id', user.id).eq('status','completed')
        .order('created_at', ascending:false).limit(30);
    return List<Map<String,dynamic>>.from(rows).reversed.toList();
  }

  static Future<bool> requestFailed(String? id) async {
    final user = SupabaseService.client.auth.currentUser;
    if (id == null || user == null) return false;
    final row = await SupabaseService.client.from('ai_consultations').select('status').eq('id', id).eq('user_id', user.id).maybeSingle();
    return row?['status'] == 'failed';
  }

  static Future<Map<String,dynamic>> consultDetailed({
    required String question, required AppLanguage language, String? requestId,
  }) async {
    final response = await SupabaseService.client.functions.invoke(
      'ai-assistant',
      body: <String,dynamic>{'mode':'consult','target_language':language.code,
        'question':question.trim(), if(requestId!=null) 'request_id':requestId},
    );
    if(response.status<200||response.status>=300) throw StateError('AI consultation failed (${response.status})');
    final data=response.data;
    if(data is! Map || '${data['answer']??''}'.trim().isEmpty) throw StateError('AI consultation returned no answer.');
    return Map<String,dynamic>.from(data);
  }

  static Future<String> consult({required String question,required AppLanguage language}) async {
    final result=await consultDetailed(question:question,language:language);
    return '${result['answer']}';
  }
}
