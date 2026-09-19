import 'app_language.dart';
import 'shared_ui_text_catalog.dart';
import 'ui_localizations.dart';
import '../services/shared_ui_text_service.dart';

/// Localizes printed furniture only. Recipient data and amounts are unchanged.
class DocumentLocalizations {
  static String text(AppLanguage language, String source) =>
      UiLocalizations.get(language, source);

  static String key(AppLanguage language, String key,
      [Map<String, Object?> values = const {}]) {
    var value = SharedUiTextService.instance.text(key, language.code,
        sharedTextDefaults[key]?[language.code] ?? sharedTextDefaults[key]?['ko'] ?? key);
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return value;
  }

  static String note(AppLanguage language, String value) {
    if (language == AppLanguage.korean) return value;
    // Translate recognized system labels, never send customer notes to a service.
    var result = value;
    for (final source in ['카톡 명세서 선공유 및 온라인 결제', '카톡 명세서 선공유', '온라인 결제', '지방 선결제', '시내 선결제', '지방배송', '시내배송', '(선결제)', ' (할인)', '추가 할인', '특별 할인', '기업 할인', '대표 고정 할인', '기타 할인']) {
      result = result.replaceAll(source, text(language, source));
    }
    result = result.replaceAllMapped(RegExp(r'할인\s+([0-9.]+)% 적용'),
      (m) => '${text(language, '할인')} ${m[1]}%');
    return result.replaceAllMapped(RegExp(r'([0-9.]+)% 적용'), (m) => '${m[1]}%');
  }
}
