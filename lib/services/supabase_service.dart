import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

abstract final class SupabaseService {
  static bool get isReady => SupabaseConfig.isConfigured;

  static SupabaseClient get client {
    if (!isReady) {
      throw StateError(
        'Supabase가 설정되지 않았습니다. --dart-define=SUPABASE_URL 및 '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY(또는 SUPABASE_ANON_KEY)를 확인하세요.',
      );
    }
    return Supabase.instance.client;
  }
}

