import 'app_language.dart';

/// Localizes shipment year/voyage values for display only.
///
/// Stored filter and database values such as `2026년` and `17항차` stay
/// unchanged so existing queries and operational data remain compatible.
class ShipmentPeriodLabels {
  ShipmentPeriodLabels._();

  static String year(dynamic value, AppLanguage language) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '';
    if (text == '전체') return AppStrings.get(language, 'all');

    final digits = RegExp(r'\d+').firstMatch(text)?.group(0) ?? '';
    if (digits.isEmpty) return text;
    switch (language) {
      case AppLanguage.korean:
        return '$digits년';
      case AppLanguage.english:
        return digits;
      case AppLanguage.lao:
        return 'ປີ $digits';
    }
  }

  static String voyage(dynamic value, AppLanguage language) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '';
    if (text == '전체') return AppStrings.get(language, 'all');

    final digits = RegExp(r'\d+').firstMatch(text)?.group(0) ?? '';
    if (digits.isEmpty) return text;
    switch (language) {
      case AppLanguage.korean:
        return '$digits항차';
      case AppLanguage.english:
        return 'Voyage $digits';
      case AppLanguage.lao:
        return 'ຖ້ຽວທີ $digits';
    }
  }
}
