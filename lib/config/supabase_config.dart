import 'package:supabase_flutter/supabase_flutter.dart';

/// Values are provided with --dart-define; never commit a service_role key.
class SupabaseConfig {
  SupabaseConfig._();

  static const String projectUrl = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      projectUrl.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(url: projectUrl, anonKey: anonKey);
  }
}
