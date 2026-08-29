import 'package:flutter/material.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'services/route_catalog_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SupabaseConfig는 --dart-define으로 전달된 값이 있을 때만 초기화합니다.
  await SupabaseConfig.initialize();

  // DB에 활성화된 운송 경로가 있으면 앱 전체 RouteCatalog에 반영합니다.
  // RPC/네트워크 오류 시 기존 내장 경로가 fallback으로 유지됩니다.
  await RouteCatalogService.instance.refresh();

  runApp(const CargoFlowApp());
}
