import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/money_format.dart';

void main() {
  test('document currencies round upward and separate symbol from amount', () {
    expect(MoneyFormat.usd(41.5), r'$ 41.50');
    expect(MoneyFormat.kip(727825), '₭ 728,000');
    expect(MoneyFormat.thb(1031.49), '฿ 1,032');
    expect(MoneyFormat.krw(41571), '₩ 41,600');
  });
}
