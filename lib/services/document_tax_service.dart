import '../config/supabase_config.dart';
import 'supabase_service.dart';

class DocumentTaxContext {
  const DocumentTaxContext({this.rate = 0, this.applicable = false, this.remark = ''});
  final double rate;
  final bool applicable;
  final String remark;

  factory DocumentTaxContext.fromJson(Map<String, dynamic> value) => DocumentTaxContext(
    rate: (value['vat_rate'] as num?)?.toDouble() ?? 0,
    applicable: value['vat_applicable'] == true,
    remark: '${value['tax_remark'] ?? ''}',
  );
}

class DocumentTaxService {
  static Future<DocumentTaxContext> forMyQuote(String routeKey) async {
    if (!SupabaseConfig.isConfigured) return const DocumentTaxContext();
    final result = await SupabaseService.client.rpc('my_freight_tax_context',
      params: {'p_route_key': routeKey});
    return DocumentTaxContext.fromJson(Map<String, dynamic>.from(result as Map));
  }

  static Future<DocumentTaxContext> forRemark(String routeKey, String remark) async {
    final result = await SupabaseService.client.rpc('document_vat_context',
      params: {'p_route_key': routeKey, 'p_remark': remark});
    return DocumentTaxContext.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
