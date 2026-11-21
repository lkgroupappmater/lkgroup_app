import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/services/customer_benefit_service.dart';

void main() {
  const phones = '020-1111-2222 / 020 3333 4444';
  const company = '예시 회사 / Example Company';
  test('discount edit preserves all phones and company aliases', () {
    final rule = DiscountRule.fromMap({
      'id': 1, 'customer_name': '회원가', 'company_name': company,
      'phone': '0201111222202033334444', 'phone_display': phones,
      'route_key': 'kr_la_air', 'discount_percent': .05, 'active': true,
    });
    expect(rule.phone, phones);
    final saved = rule.toMap();
    expect(saved['phone_display'], phones);
    expect(saved['phone'], '0201111222202033334444');
    expect(saved['company_name'], company);
    expect(saved['discount_percent'], .05);
    expect(saved['active'], true);
  });
  test('older discount rows retain their phone when display is absent or empty', () {
    for (final value in [null, '']) {
      final rule = DiscountRule.fromMap({
        'customer_name': '회원가', 'phone': '02011112222',
        'phone_display': value, 'discount_percent': .05,
      });
      expect(rule.phone, '02011112222');
    }
  });
  test('a multi-member discount retains ordered names and ordered numbers', () {
    final rule = DiscountRule.fromMap({
      'customer_name': '회원가/회원나/회원다(회원라)/회원마',
      'company_name': 'Example Association', 'phone_display': '02011110001 / 02011110002 / 01011110003 / 02011110004 / 02011110005',
      'discount_percent': .05, 'active': true,
    });
    final saved = rule.toMap();
    expect(saved['customer_name'], rule.customerName);
    expect(saved['phone_display'], rule.phone);
    expect(saved['company_name'], 'Example Association');
  });
}
