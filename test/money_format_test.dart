import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/money_format.dart';

void main() {
  test('currency-labelled amounts omit symbols and retain rounding', () {
    expect(MoneyFormat.usdNumber(41.5), '41.50');
    expect(MoneyFormat.kipNumber(727825), '728,000');
    expect(MoneyFormat.thbNumber(1031.49), '1,032');
    expect(MoneyFormat.krwNumber(41571), '41,600');
    expect(MoneyFormat.usdNumber(0), '0.00');
    expect(MoneyFormat.usdNumber(-20), '-20.00');
  });

  test('document currencies round upward and separate symbol from amount', () {
    expect(MoneyFormat.usd(41.5), r'$ 41.50');
    expect(MoneyFormat.kip(727825), '₭ 728,000');
    expect(MoneyFormat.thb(1031.49), '฿ 1,032');
    expect(MoneyFormat.krw(41571), '₩ 41,600');
  });
}
