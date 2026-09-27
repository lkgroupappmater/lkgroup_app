import 'waybill_intake_service.dart';

class CustomerIdentityService {
  static String? normalizeCode(String value) {
    final match = RegExp(r'^(?:(?:ID|LK)\s*[:#-]?\s*)?(\d{1,9})$', caseSensitive: false).firstMatch(value.trim());
    final number = match == null ? null : int.tryParse(match.group(1)!);
    return number == null || number <= 0 ? null : number.toString().padLeft(3, '0');
  }
  static String displayCode(Object? value) {
    final code = normalizeCode('${value ?? ''}');
    return code == null ? '${value ?? ''}' : 'LK ${code.padLeft(4, '0')}';
  }
  static Future<void> enrichMembers(List<Map<String, dynamic>> members) async {
    for (var start = 0; start < members.length; start += 200) {
      final group = members.skip(start).take(200).toList();
      final response = await WaybillIntakeService.call('customer_identity_index', {'profile_ids': group.map((m) => m['id']).toList()});
      final codes = {for (final m in response['profiles'] as List) '${m['id']}': m};
      for (final m in group) { m['customer_code'] = codes['${m['id']}']?['customer_code']; m['identity_status'] = codes['${m['id']}']?['status']; }
    }
  }
  static Future<Map<int, String>> deliveryCodes(List<int> ids) async {
    final result = <int, String>{};
    for (var start = 0; start < ids.length; start += 500) {
      final response = await WaybillIntakeService.call('delivery_customer_index', {'delivery_ids': ids.skip(start).take(500).toList()});
      for (final row in response['deliveries'] as List) {
        if (row['customer_code'] != null) result[(row['id'] as num).toInt()] = '${row['customer_code']}';
      }
    }
    return result;
  }
}
