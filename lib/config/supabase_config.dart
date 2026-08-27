import 'package:supabase_flutter/supabase_flutter.dart';

/// Runtime configuration supplied with --dart-define.
/// Never commit a database password or service_role key.
class SupabaseConfig {
  SupabaseConfig._();

  static const String projectUrl =
      String.fromEnvironment('https://rkqwzxfcnciptnwesfbr.supabase.co', defaultValue: '');
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
