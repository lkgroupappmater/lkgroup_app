import 'package:supabase_flutter/supabase_flutter.dart';

/// Runtime configuration supplied with --dart-define.
/// Never commit a database password or service_role key.
class SupabaseConfig {
  SupabaseConfig._();

  // 실제 값은 소스에 직접 넣지 않고 --dart-define으로 전달합니다.
  // 예: --dart-define=SUPABASE_URL=https://your-project.supabase.co
  static const String projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  static bool get isConfigured =>
      projectUrl.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: projectUrl,
      publishableKey: publishableKey,
    );
  }
}


