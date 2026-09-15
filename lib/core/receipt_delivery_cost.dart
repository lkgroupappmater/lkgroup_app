import '../services/receipt_extra_cost_service.dart';

/// Delivery fees are manually priced; a suggested row is never saved as zero.
class ReceiptDeliveryCost {
  ReceiptDeliveryCost._();

  static String name(String? type) => switch (type) {
    'province' => '지방배송',
    'city' => '시내배송',
    _ => '',
  };

  static String? prepaidType(
    Iterable<Map<String, dynamic>> rows, {
    String? profileType,
    bool profilePrepaid = false,
  }) {
    if (profileType != null) {
      return profilePrepaid && ['province', 'city'].contains(profileType)
          ? profileType
          : null;
    }
    final pattern = RegExp(
      r'(지방배송|시내배송|provincialdelivery|provincedelivery|citydelivery)'
      r'(선결제|선결재|선불|prepaid|payinadvance)?',
    );
    for (final row in rows) {
      final note = '${row['special_note_auto'] ?? ''}'.trim();
      final normalized = (note.isEmpty ? '${row['special_note'] ?? ''}' : note)
          .toLowerCase()
          .replaceAll(RegExp(r'[\s_\-()（）:：]+'), '');
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;
      if (match[2] == null) return null;
      return ['시내배송', 'citydelivery'].contains(match[1]) ? 'city' : 'province';
    }
    return null;
  }

  static String? typeOf(ExtraCostItem cost) {
    if (['province', 'city'].contains(cost.deliveryType))
      return cost.deliveryType;
    final text = cost.name.toLowerCase().replaceAll(RegExp(r'\s'), '');
    if (RegExp(r'^(지방배송|provincialdelivery|provincedelivery)(비|비용|fee|cost)?$')
        .hasMatch(text))
      return 'province';
    if (RegExp(r'^(시내배송|citydelivery)(비|비용|fee|cost)?$').hasMatch(text))
      return 'city';
    return null;
  }

  static List<ExtraCostItem> forStatement(
    List<ExtraCostItem> costs,
    String? type,
  ) {
    if (type == null || costs.any((cost) => typeOf(cost) == type)) return costs;
    return [
      ...costs,
      ExtraCostItem(
        name: name(type),
        amountUsd: 0,
        deliveryType: type,
        pending: true,
      ),
    ];
  }
}
