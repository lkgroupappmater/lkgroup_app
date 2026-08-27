import 'package:supabase_flutter/supabase_flutter.dart';

/// Runtime configuration supplied with --dart-define.
/// Never commit a database password or service_role key.
class SupabaseConfig {
  SupabaseConfig._();

  // 실제 값은 소스에 직접 넣지 않고 --dart-define으로 전달합니다.
  // 예: --dart-define=SUPABASE_URL=https://your-project.supabase.co
  static const String projectUrl = String.fromEnvironment(
    'https://rkqwzxfcnciptnwesfbr.supabase.co',
    defaultValue: '',
  );
  static const String publishableKey = String.fromEnvironment(
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJrcXd6eGZjbmNpcHRud2VzZmJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1Njc3MTAsImV4cCI6MjEwMzE0MzcxMH0.TttUKX7et6xSv-eRNHYfKe-ZX6FFmcoiIw8KR1nhJDE',
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

