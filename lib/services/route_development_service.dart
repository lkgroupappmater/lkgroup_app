import '../core/route_catalog.dart';
import 'route_catalog_service.dart';
import 'supabase_service.dart';

class RouteDevelopmentService {
  RouteDevelopmentService._();
  static final instance = RouteDevelopmentService._();

  Future<List<Map<String, dynamic>>> listRoutes() async {
    final rows =
        await SupabaseService.client.rpc('admin_route_definitions') as List;
    return rows
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> rates(String key) async {
    final rows = await SupabaseService.client
        .from('freight_rate_tiers')
        .select()
        .eq('route_key', key)
        .eq('active', true)
        .order('min_weight_kg');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> draftRates(String key) async {
    final rows = await SupabaseService.client
        .from('freight_rate_tiers')
        .select()
        .eq('route_key', key)
        .order('min_weight_kg');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  Future<void> updateDraft({
    required String key,
    required String label,
    required String company,
    required String phone,
    required String address,
    required String boxPrefix,
    required String receiptPrefix,
    required String filePrefix,
    required double minimumCharge,
    required List<Map<String, double>> tiers,
    required List<Map<String, String>> templateOverrides,
  }) async {
    await SupabaseService.client.rpc(
      'admin_update_route_draft',
      params: {
        'p_route_key': key,
        'p_label': label,
        'p_company_name': company,
        'p_phone': phone,
        'p_address': address,
        'p_box_prefix': boxPrefix,
        'p_receipt_prefix': receiptPrefix,
        'p_minimum_charge': minimumCharge,
        'p_tiers': tiers,
      },
    );

    await _saveExtension(
      key: key,
      filePrefix: filePrefix,
      templateOverrides: templateOverrides,
    );
  }

  Future<void> saveExisting({
    required String key,
    required String label,
    required String company,
    required String phone,
    required String address,
    required String boxPrefix,
    required String receiptPrefix,
    required String filePrefix,
    required double volumetricFactor,
    required double minimumCharge,
    required List<Map<String, double>> tiers,
    required List<Map<String, String>> templateOverrides,
  }) async {
    await SupabaseService.client.rpc(
      'admin_save_route_definition',
      params: {
        'p_route_key': key,
        'p_label': label,
        'p_company_name': company,
        'p_phone': phone,
        'p_address': address,
        'p_box_prefix': boxPrefix,
        'p_receipt_prefix': receiptPrefix,
        'p_volumetric_factor': volumetricFactor,
        'p_minimum_charge': minimumCharge,
        'p_tiers': tiers,
      },
    );

    await _saveExtension(
      key: key,
      filePrefix: filePrefix,
      templateOverrides: templateOverrides,
    );

    await _cloneBase(key);
    await RouteCatalogService.instance.refresh();
  }

  Future<String> createDraft({
    required String label,
    required String baseRouteKey,
    required String company,
    required String phone,
    required String address,
    required String boxPrefix,
    required String receiptPrefix,
    required String filePrefix,
    required double volumetricFactor,
    required double minimumCharge,
    required List<Map<String, double>> tiers,
    required List<Map<String, String>> templateOverrides,
  }) async {
    final result = await SupabaseService.client.rpc(
      'admin_create_route_draft',
      params: {
        'p_label': label,
        'p_base_route_key': baseRouteKey,
        'p_company_name': company,
        'p_phone': phone,
        'p_address': address,
        'p_box_prefix': boxPrefix,
        'p_receipt_prefix': receiptPrefix,
        'p_volumetric_factor': volumetricFactor,
        'p_minimum_charge': minimumCharge,
        'p_tiers': tiers,
      },
    );

    final key = '$result';
    await _saveExtension(
      key: key,
      filePrefix: filePrefix,
      templateOverrides: templateOverrides,
    );
    return key;
  }

  Future<void> applyDraft(String key) async {
    // BASE 생성이 실패하면 draft는 활성화하지 않습니다.
    await _cloneBase(key);
    await SupabaseService.client.rpc(
      'admin_apply_route_draft',
      params: {'p_route_key': key},
    );
    await RouteCatalogService.instance.refresh();
  }


  Future<void> restoreRoute(String key) async {
    await SupabaseService.client.rpc(
      'admin_restore_deleted_route',
      params: {'p_route_key': key},
    );
    await RouteCatalogService.instance.refresh();
  }

  Future<void> deleteRoute(String key) async {
    await SupabaseService.client.rpc(
      'admin_soft_delete_route',
      params: {'p_route_key': key},
    );
    await RouteCatalogService.instance.refresh();
  }

  Future<void> _saveExtension({
    required String key,
    required String filePrefix,
    required List<Map<String, String>> templateOverrides,
  }) async {
    await SupabaseService.client.rpc(
      'admin_set_route_extension',
      params: {
        'p_route_key': key,
        'p_file_prefix': filePrefix,
        'p_template_overrides': templateOverrides,
      },
    );
  }

  Future<void> _cloneBase(String key) async {
    final response = await SupabaseService.client.functions.invoke(
      'clone-route-base',
      body: {'route_key': key},
    );
    if (response.status < 200 || response.status >= 300) {
      String detail = '${response.data}';
      if (response.data is Map &&
          (response.data as Map)['error'] != null) {
        detail = '${(response.data as Map)['error']}';
      }
      throw StateError('BASE Excel 생성/갱신 실패: $detail');
    }
  }

  String formRouteKeyFor(String routeKey) =>
      RouteCatalog.formRouteKeyFor(routeKey);
}
