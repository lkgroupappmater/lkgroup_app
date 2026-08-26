import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 연결 설정입니다.
///
/// 실제 값은 소스 코드에 저장하지 않고 실행 시 dart-define으로 전달합니다.
///
/// flutter run \\
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \\
///   --dart-define=SUPABASE_ANON_KEY=your-anon-key
///
/// anon key는 클라이언트 앱에 사용되는 공개 키이지만, service_role key와
/// 데이터베이스 비밀번호는 절대로 앱이나 GitHub에 넣으면 안 됩니다.
class SupabaseConfig {
  SupabaseConfig._();

  static const String projectUrl = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      projectUrl.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  /// 설정값이 있을 때만 Supabase를 초기화합니다.
  static Future<void> initialize() async {
    if (!isConfigured) {
      return;
    }

    await Supabase.initialize(
      url: projectUrl,
      publishableKey: anonKey,
    );
  }
}

