import 'package:intl/intl.dart';

/// App-wide money/number formatter.
///
/// - thousands separator: ,
/// - decimal separator: .
/// - USD keeps 2 decimals
/// - KIP rounds upward to 1,000, THB to 1, KRW to 100
class MoneyFormat {
  MoneyFormat._();

  static final NumberFormat _whole = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _two = NumberFormat('#,##0.00', 'en_US');

  static String number(num value, {int decimals = 0}) {
    if (decimals <= 0) return _whole.format(value);
    return _two.format(value);
  }

  static num _roundUpTo(num value, num unit) {
    if (!value.isFinite || unit <= 0) return value;
    return ((value / unit) - 0.000000001).ceil() * unit;
  }

  static num roundKip(num value) => _roundUpTo(value, 1000);
  static num roundThb(num value) => _roundUpTo(value, 1);
  static num roundKrw(num value) => _roundUpTo(value, 100);

  static String kipNumber(num value) => number(roundKip(value));
  static String thbNumber(num value) => number(roundThb(value));
  static String krwNumber(num value) => number(roundKrw(value));

  static String usd(num value) => '\$${number(value, decimals: 2)}';
  static String kip(num value) => '₭${kipNumber(value)}';
  static String thb(num value) => '฿${thbNumber(value)}';
  static String krw(num value) => '₩${krwNumber(value)}';
}
