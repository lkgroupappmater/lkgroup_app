import '../config/supabase_config.dart';
import '../core/route_catalog.dart';
import 'supabase_service.dart';

class RouteCatalogService {
  RouteCatalogService._();
  static final instance = RouteCatalogService._();

  Future<void> refresh() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final raw =
          await SupabaseService.client.rpc('list_active_route_definitions');
      final rows = List<Map<String, dynamic>>.from(raw as List);
      RouteCatalog.applyDatabaseDefinitions(rows);
    } catch (_) {
      // SQL 적용 전/일시 네트워크 오류에는 기존 내장 11개 경로를 안전하게 유지합니다.
    }
  }
}
