import 'package:flutter/material.dart';

import 'app.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SupabaseConfig는 --dart-define으로 전달된 값이 있을 때만 초기화합니다.
  // 실행 예:
  // flutter run -d emulator-5554 \
  //   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  //   --dart-define=SUPABASE_ANON_KEY=your-anon-key
  await SupabaseConfig.initialize();

  runApp(const CargoFlowApp());
}
