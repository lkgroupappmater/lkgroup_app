import 'app_language.dart';
import 'shared_ui_text_catalog.dart';
import 'ui_localizations.dart';

/// Fixed operational UI copy only. Call at the display boundary, never when
/// reading/writing customer fields, filtering records or creating identifiers.
class OperationalLocalizations {
  OperationalLocalizations._();

  /// API status codes remain unchanged; only the visible label is localized.
  static String status(AppLanguage language, String value) {
    const labels = <String, List<String>>{
      'pending': ['대기', 'Pending', 'ລໍຖ້າ'],
      'reviewing': ['검토 중', 'Under review', 'ກຳລັງກວດສອບ'],
      'approved': ['승인됨', 'Approved', 'ອະນຸມັດແລ້ວ'],
      'rejected': ['거절됨', 'Rejected', 'ປະຕິເສດແລ້ວ'],
      'completed': ['완료', 'Completed', 'ສຳເລັດ'],
    };
    final label = labels[value];
    return label == null ? value : sharedText(language, label[0], label[1], label[2]);
  }

  static final _templates = sharedKoreanTextKeys.keys
      .where((source) => RegExp(r'\{p\d+\}').hasMatch(source))
      .map((source) {
        final variables = RegExp(r'\{p\d+\}').allMatches(source).toList();
        var pattern = '^';
        var offset = 0;
        for (final variable in variables) {
          pattern += RegExp.escape(source.substring(offset, variable.start));
          pattern += r'([\s\S]*?)';
          offset = variable.end;
        }
        pattern += RegExp.escape(source.substring(offset)) + r'$';
        return (source: source, pattern: RegExp(pattern),
          names: variables.map((m) => m.group(0)!).toList(),
          fixedLength: source.replaceAll(RegExp(r'\{p\d+\}'), '').length);
      }).toList()..sort((a, b) => b.fixedLength.compareTo(a.fixedLength));

  static String text(AppLanguage language, String source) {
    if (sharedKoreanTextKeys.containsKey(source)) {
      return UiLocalizations.get(language, source);
    }
    if (language == AppLanguage.korean || !RegExp(r'[가-힣]').hasMatch(source)) {
      return source;
    }
    for (final item in _templates) {
      final match = item.pattern.firstMatch(source);
      if (match == null) continue;
      final translated = UiLocalizations.get(language, item.source);
      final values = <String, String>{
        for (var i = 0; i < item.names.length; i++)
          item.names[i]: match.group(i + 1) ?? '',
      };
      // One pass preserves literal braces and placeholders in customer data.
      return translated.replaceAllMapped(RegExp(r'\{p\d+\}'),
          (variable) => values[variable.group(0)] ?? variable.group(0)!);
    }
    return UiLocalizations.get(language, source);
  }
}
