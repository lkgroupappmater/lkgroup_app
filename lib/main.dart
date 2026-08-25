import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'services/supabase_connection_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );

    // 연결 테스트용입니다. shipments 테이블과 조회 정책이 준비되면
    // debug console에 최대 5건의 결과가 출력됩니다.
    try {
      final data = await SupabaseConnectionService.testConnection();
      debugPrint('Supabase connection OK: ${data.length} shipment(s)');
    } catch (error, stackTrace) {
      // 앱 실행은 계속하고, 테이블/RLS 설정 문제만 로그로 확인합니다.
      debugPrint('Supabase table test failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  } catch (error, stackTrace) {
    // 초기화 실패가 UI 실행 자체를 막지 않도록 처리합니다.
    debugPrint('Supabase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const CargoFlowApp());
}
