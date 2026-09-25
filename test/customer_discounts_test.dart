import 'package:flutter_test/flutter_test.dart';
import '../lib/core/customer_discounts.dart';
void main() {
  test('legacy special rates and the common split contract use separate lines', () {
    expect(CustomerDiscounts.split({'discount_percent': .05, 'group_name': '특별할인'}), (regular: 0.0, special: .05));
    expect(CustomerDiscounts.split({'discount_percent': .2, 'group_name': '기업 할인'}), (regular: .2, special: 0.0));
    expect(CustomerDiscounts.split({'discount_percent': .25, 'regular_discount_percent': .2, 'special_discount_percent': .05}), (regular: .2, special: .05));
  });
  test('both Row data lists survive import in either section order', () {
    Map<String, dynamic> rule(String group, double rate) => {
      'customer_name': 'Discount QA', 'phone': '02099999999', 'route_key': 'kr_la_sea',
      'group_name': group, 'discount_percent': rate,
    };
    final normal=rule('기업 할인',.2), special=rule('특별할인',.05);
    for (final source in [[normal,special],[special,normal]]) {
      final result=CustomerDiscounts.mergeImportRules(source);
      expect(result, hasLength(1));
      expect(result.single['discount_percent'],.25);
      expect(result.single['special_discount_percent'],.05);
      expect(result.single['group_name'],'기업 할인');
    }
    expect(()=>CustomerDiscounts.mergeImportRules([rule('기업 할인',.9),rule('특별할인',.2)]),throwsStateError);
  });
}
