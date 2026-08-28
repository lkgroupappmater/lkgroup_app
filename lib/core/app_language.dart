// lib/core/app_language.dart
// Full replacement – keeps enum, adds flag helpers and consultation templates.
// TODO: Connect to admin/DB for runtime language override and AI translation API.

enum AppLanguage { korean, english, lao }

// ── Flag & label helpers ─────────────────────────────────────────────────────
extension AppLanguageExt on AppLanguage {
  String get flag {
    switch (this) {
      case AppLanguage.korean:
        return '🇰🇷';
      case AppLanguage.english:
        return '🇬🇧';
      case AppLanguage.lao:
        return '🇱🇦';
    }
  }

  String get label {
    switch (this) {
      case AppLanguage.korean:
        return '한국어';
      case AppLanguage.english:
        return 'English';
      case AppLanguage.lao:
        return 'ລາວ';
    }
  }

  String get flagLabel => '$flag $label';
}

class AppStrings {
  AppStrings._();

  static const Map<AppLanguage, Map<String, String>> values = {
    AppLanguage.korean: {
      'home_title': 'LK Group',
      'tracking_title': '화물 조회',
      'quote_title': '운임 확인',
      'account_title': '계정',
      'tracking': '화물 조회',
      'quote': '운임 확인',
      'account': '계정',
      'chip_quote': '운임 견적',
    },
    AppLanguage.english: {
      'home_title': 'LK Group',
      'tracking_title': 'Cargo Tracking',
      'quote_title': 'Freight Request',
      'account_title': 'Account',
      'tracking': 'Tracking',
      'quote': 'Freight',
      'account': 'Account',
      'chip_quote': 'Quote',
    },
    AppLanguage.lao: {
      'home_title': 'LK Group',
      'tracking_title': 'ກວດສອບສິນຄ້າ',
      'quote_title': 'ຂໍຄ່າຂົນສົ່ງ',
      'account_title': 'ບັນຊີ',
      'tracking': 'ກວດສອບ',
      'quote': 'ຄ່າຂົນສົ່ງ',
      'account': 'ບັນຊີ',
      'chip_quote': 'ລາຄາ',
    },
  };

  static String get(AppLanguage language, String key) =>
      values[language]?[key] ?? values[AppLanguage.korean]?[key] ?? key;
}
