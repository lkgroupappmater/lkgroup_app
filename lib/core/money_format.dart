import 'package:intl/intl.dart';

/// App-wide money/number formatter.
///
/// - thousands separator: ,
/// - decimal separator: .
/// - USD/THB keep up to 2 decimals when needed
/// - KIP/KRW default to whole units
class MoneyFormat {
  MoneyFormat._();

  static final NumberFormat _whole = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _two = NumberFormat('#,##0.00', 'en_US');

  static String number(num value, {int decimals = 0}) {
    if (decimals <= 0) return _whole.format(value);
    return _two.format(value);
  }

  static String usd(num value) => '\$${number(value, decimals: 2)}';
  static String kip(num value) => '₭${number(value)}';
  static String thb(num value) => '฿${number(value, decimals: 2)}';
  static String krw(num value) => '₩${number(value)}';
}
