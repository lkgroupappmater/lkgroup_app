import 'package:flutter/material.dart';

import 'app.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SUPABASE_URL과 SUPABASE_ANON_KEY를 --dart-define으로 전달하면
  // 앱 시작 전에 Supabase가 초기화됩니다.
  await SupabaseConfig.initialize();

  runApp(const CargoFlowApp());
}
