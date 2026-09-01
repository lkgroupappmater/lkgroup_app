from pathlib import Path

cwd = Path.cwd()

def read(path):
    return path.read_text(encoding='utf-8-sig')

def write(path, text):
    path.write_text(text, encoding='utf-8')

# 1) BASE discount group name detection
p = cwd / 'lib/services/excel_import_service.dart'
s = read(p)
start = s.find('  String _discountGroupNameForSheet(')
end = s.find('  Future<int> _importStatementShareRules(', start)
if start < 0 or end < 0:
    raise SystemExit('discount group helper block not found')

new_helper = r'''  String _discountGroupNameForSheet(
    List<List<String>> sheet, {
    required int headerRow,
    required int customerColumn,
  }) {
    String clean(String raw) {
      var text = raw.trim();
      text = text
          .replaceAll(RegExp(r'customer\\s*list', caseSensitive: false), '')
          .replaceAll(RegExp(r'discount\\s*list', caseSensitive: false), '')
          .replaceAll(RegExp(r'customer\\s*discount', caseSensitive: false), '')
          .replaceAll('고객 리스트', '')
          .replaceAll('고객리스트', '')
          .replaceAll('할인 고객 리스트', '')
          .replaceAll('할인고객리스트', '')
          .replaceAll('할인 고객', '')
          .replaceAll('할인고객', '')
          .replaceAll(RegExp(r'\\s+'), ' ')
          .trim();

      text = text
          .replaceFirst(RegExp(r'\\s+고객$'), '')
          .replaceFirst(RegExp(r'\\s+list$', caseSensitive: false), '')
          .trim();
      return text;
    }

    bool isGeneric(String raw) {
      final key = raw
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\\s_./()-]+'), '');
      const generic = <String>{
        '할인',
        '할인율',
        '할인금액',
        '할인액',
        '할인적용',
        'discount',
        'discountrate',
        'discountamount',
        'name',
        'customer',
        'customername',
        'phone',
        'tel',
        '연락처',
        '전화번호',
        '이름',
        '성명',
        '고객명',
      };
      return generic.contains(key);
    }

    int semanticScore(String raw) {
      final v = raw.trim().toLowerCase();
      if (v.isEmpty || isGeneric(v)) return -9999;
      if (_isCustomerNameHeader(v) ||
          _isDiscountHeader(v) ||
          _isPhoneHeader(v)) {
        return -9999;
      }

      var score = 0;
      const strong = <String>[
        '라선협',
        '지상사',
        '협의회',
        '회원사',
        '법인장',
        '지인',
        '아파트',
        '기업',
        '특별',
        '파트너',
        '협력사',
        '임직원',
      ];
      for (final token in strong) {
        if (v.contains(token)) score += 100;
      }
      if (v.contains('할인')) score += 20;
      if (v.contains('협')) score += 15;

      if (RegExp(r'^\\d+(\\.\\d+)?%?$').hasMatch(v)) return -9999;
      if (RegExp(r'^\\+?\\d[\\d\\s-]{6,}$').hasMatch(v)) return -9999;

      return score;
    }

    String best = '';
    var bestScore = -9999;

    final minRow = headerRow - 20 < 0 ? 0 : headerRow - 20;
    for (var rr = headerRow; rr >= minRow; rr--) {
      final row = sheet[rr];
      if (row.isEmpty) continue;
      final startCol = customerColumn - 10 < 0 ? 0 : customerColumn - 10;
      final endCol = customerColumn + 10 < row.length
          ? customerColumn + 10
          : row.length - 1;

      for (var cc = startCol; cc <= endCol; cc++) {
        final raw = row[cc].trim();
        final semantic = semanticScore(raw);
        if (semantic < 0) continue;

        final distance =
            (headerRow - rr).abs() * 2 + (customerColumn - cc).abs();
        final score = semantic - distance;
        if (score > bestScore) {
          final cleaned = clean(raw);
          if (cleaned.isNotEmpty && !isGeneric(cleaned)) {
            best = cleaned;
            bestScore = score;
          }
        }
      }
    }
    return best;
  }

'''
s = s[:start] + new_helper + s[end:]
write(p, s)

# 2) Statement preview percentage and generic group cleanup
p = cwd / 'lib/screens/statement_preview_dialog.dart'
s = read(p)

marker = '''    final freightGroups = freight.lines
        .map((line) => line.discountGroup.trim())'''
if marker not in s:
    raise SystemExit('statement freightGroups marker not found')

replacement = '''    bool validDiscountGroup(String value) {
      final key = value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\\s_./()-]+'), '');
      return key.isNotEmpty &&
          key != '할인' &&
          key != '할인율' &&
          key != '할인금액' &&
          key != '할인액' &&
          key != 'discount' &&
          key != 'discountrate' &&
          key != 'discountamount' &&
          key != '기타할인';
    }

    final freightGroups = freight.lines
        .map((line) => line.discountGroup.trim())
        .where(validDiscountGroup)'''
s = s.replace(marker, replacement, 1)

old = '''    final discountPercentText = baseDiscountPercent > 0
        ? '${(baseDiscountPercent * 100).toStringAsFixed(
            ((baseDiscountPercent * 100) -
                        (baseDiscountPercent * 100).roundToDouble())
                    .abs() <
                .001
                ? 0
                : 2,
          )}%'
        : '';'''
new = '''    final lineDiscountPercent = freight.lines
        .map((line) => line.discountPercent)
        .fold<double>(0, (best, value) => value > best ? value : best);
    final discountPercentText = lineDiscountPercent > 0
        ? '${(lineDiscountPercent * 100).toStringAsFixed(
            ((lineDiscountPercent * 100) -
                        (lineDiscountPercent * 100).roundToDouble())
                    .abs() <
                .001
                ? 0
                : 2,
          )}%'
        : '';'''
if old in s:
    s = s.replace(old, new, 1)

s = s.replace(
'''    final discountLabel = actualDiscountPctText.isEmpty
        ? '할인'
        : '${discountGroupText.isEmpty ? '할인' : discountGroupText} '
            '$actualDiscountPctText';''',
'''    final discountLabel = actualDiscountPctText.isEmpty
        ? '할인'
        : '할인 $actualDiscountPctText';''',
1)

old_phrase = '''      final group = freightGroups.isEmpty ? '할인' : freightGroups.first;
      final phrase = group.contains('할인')
          ? '$group ${pctText(freightDiscountPercent)}% 적용'
          : '$group 할인 ${pctText(freightDiscountPercent)}% 적용';'''
new_phrase = '''      final group = freightGroups.isEmpty ? '' : freightGroups.first;
      final phrase = group.isEmpty
          ? '할인 ${pctText(freightDiscountPercent)}% 적용'
          : (group.contains('할인')
              ? '$group ${pctText(freightDiscountPercent)}% 적용'
              : '$group 할인 ${pctText(freightDiscountPercent)}% 적용');'''
if old_phrase in s:
    s = s.replace(old_phrase, new_phrase, 1)

write(p, s)
print('Patch179 applied.')
