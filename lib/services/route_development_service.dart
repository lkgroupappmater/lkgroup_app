import '../services/supabase_service.dart';

class RouteDevelopmentService {
  RouteDevelopmentService._();
  static final instance=RouteDevelopmentService._();

  Future<List<Map<String,dynamic>>> listRoutes() async {
    final rows=await SupabaseService.client.rpc('admin_route_definitions') as List;
    return rows.map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String,dynamic>>> rates(String key) async {
    final rows=await SupabaseService.client.from('freight_rate_tiers')
      .select().eq('route_key',key).eq('active',true).order('min_weight_kg');
    return rows.map((e)=>Map<String,dynamic>.from(e)).toList();
  }

  Future<void> saveExisting({
    required String key, required String label, required String company,
    required String phone, required String address, required String boxPrefix,
    required String receiptPrefix, required double volumetricFactor,
    required double minimumCharge, required List<Map<String,double>> tiers,
  }) async {
    await SupabaseService.client.rpc('admin_save_route_definition',params:{
      'p_route_key':key,'p_label':label,'p_company_name':company,'p_phone':phone,
      'p_address':address,'p_box_prefix':boxPrefix,'p_receipt_prefix':receiptPrefix,
      'p_volumetric_factor':volumetricFactor,'p_minimum_charge':minimumCharge,
      'p_tiers':tiers,
    });
  }

  Future<String> createDraft({
    required String label, required String baseRouteKey, required String company,
    required String phone, required String address, required String boxPrefix,
    required String receiptPrefix, required double volumetricFactor,
    required double minimumCharge, required List<Map<String,double>> tiers,
  }) async {
    final result=await SupabaseService.client.rpc('admin_create_route_draft',params:{
      'p_label':label,'p_base_route_key':baseRouteKey,'p_company_name':company,
      'p_phone':phone,'p_address':address,'p_box_prefix':boxPrefix,
      'p_receipt_prefix':receiptPrefix,'p_volumetric_factor':volumetricFactor,
      'p_minimum_charge':minimumCharge,'p_tiers':tiers,
    });
    return '$result';
  }

  Future<void> applyDraft(String key) async {
    await SupabaseService.client.rpc('admin_apply_route_draft',params:{'p_route_key':key});
  }
}
