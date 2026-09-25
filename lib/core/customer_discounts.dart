/// Split the common DB total without changing the existing additive basis.
class CustomerDiscounts {
  CustomerDiscounts._();
  static double _number(dynamic value) => double.tryParse('$value') ?? 0;
  static bool isSpecial(dynamic name) => '$name'.replaceAll(RegExp(r'\s'), '') == '특별할인';

  static ({double regular, double special}) split(Map<String, dynamic>? rule) {
    final values = rule ?? const <String, dynamic>{};
    final special = _number(values['special_discount_percent'] ??
        (isSpecial(values['group_name']) ? values['discount_percent'] : 0))
        .clamp(0, 1).toDouble();
    final regular = _number(values['regular_discount_percent'] ??
        (_number(values['discount_percent']) - special)).clamp(0, 1).toDouble();
    return (regular: regular, special: special);
  }

  static List<Map<String, dynamic>> mergeImportRules(List<Map<String, dynamic>> rules) {
    final merged = <String, Map<String, dynamic>>{};
    for (final rule in rules) {
      final key = '${rule['customer_name'] ?? ''}|${rule['phone'] ?? ''}|${rule['route_key'] ?? ''}';
      final previous = merged[key];
      final specialRule = isSpecial(rule['group_name']);
      final oldSpecial = _number(previous?['special_discount_percent']);
      final ordinary = specialRule ? _number(previous?['discount_percent']) - oldSpecial : _number(rule['discount_percent']);
      final special = specialRule ? _number(rule['discount_percent']) : oldSpecial;
      if (ordinary + special > 1) {
        throw StateError('일반 할인과 특별할인의 합계는 100%를 초과할 수 없습니다.');
      }
      merged[key] = {
        ...(specialRule && previous != null && ordinary > 0 ? previous : rule),
        'discount_percent': ordinary + special,
        'special_discount_percent': special,
      };
    }
    return merged.values.toList(growable: false);
  }
}
