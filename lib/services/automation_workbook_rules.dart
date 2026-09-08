/// Parses the separate input sheets in the approved SEA/AIR workbooks.
/// Formula helper columns are intentionally outside the input ranges.
class AutomationWorkbookRules {
  static String key(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'[\s,·ㆍ._/()\-]+'), '');
  static String digits(String value) => value.replaceAll(RegExp(r'\D'), '');
  static String cell(List<String> row, int column) => column < row.length ? row[column].trim() : '';
  static bool selected(String value) => RegExp(r'^(사용|선택|1|true|yes|y|✓|✔)$', caseSensitive: false).hasMatch(value.trim());

  static List<Map<String, dynamic>>? deliveries(
    Map<String, List<List<String>>> workbook,
    String routeKey, {
    int Function(String sheet, int row)? colorPriority,
  }) {
    final sheets = workbook.entries.where((e) => ['지방배송', '시내배송'].contains(key(e.key))).toList();
    if (sheets.isEmpty || !['kr_la_sea', 'kr_la_air', 'th_la_land'].contains(routeKey)) return null;
    final result = <int, Map<String, dynamic>>{};
    for (final sheet in sheets) {
      final city = key(sheet.key) == '시내배송';
      final header = sheet.value.indexWhere((r) => ['no', '번호'].contains(key(cell(r, 0))) && ['name', '이름', '고객명'].contains(key(cell(r, 1))));
      if (header < 0) throw StateError('${sheet.key}: No./Name 제목 행을 확인하세요.');
      int? number;
      final block = <int>[];
      void flush() {
        if (number == null || block.isEmpty) return;
        String first(int c) => block.map((r) => cell(sheet.value[r], c)).firstWhere((v) => v.isNotEmpty, orElse: () => '');
        final name = first(1), alternate = first(3);
        if (name.isEmpty && alternate.isEmpty) { block.clear(); return; }
        final candidates = block.where((r) => cell(sheet.value[r], 5).isNotEmpty || cell(sheet.value[r], 6).isNotEmpty).toList();
        if (candidates.isEmpty) { block.clear(); return; }
        final marked = candidates.where((r) => selected(cell(sheet.value[r], 7))).toList();
        if (marked.length > 1) throw StateError('${sheet.key} $number번: 사용선택은 한 행만 지정하세요.');
        final destinations = candidates.where((r) => cell(sheet.value[r], 6).isNotEmpty).toList();
        destinations.sort((a, b) {
          final priority = (colorPriority?.call(sheet.key, b) ?? 1).compareTo(colorPriority?.call(sheet.key, a) ?? 1);
          return priority != 0 ? priority : a.compareTo(b);
        });
        final chosen = marked.isNotEmpty ? marked.first : city || destinations.isEmpty ? candidates.first : destinations.first;
        final row = sheet.value[chosen], phone = first(4);
        final prepaid = RegExp(r'선결제|선결재|payinadvance|prepaid').hasMatch(key('${first(2)} ${cell(row, 2)} ${cell(row, 6)}'));
        var sourceNo = city ? 10000 + number! : number!;
        if (result.containsKey(sourceNo)) sourceNo = 100000 + (city ? 10000 : 0) + block.first + 1;
        result[sourceNo] = {
          'source_no': sourceNo, 'original_source_no': number,
          'source_sheet': sheet.key, 'source_row': block.first + 1,
          'customer_name': name, 'alternate_name': alternate, 'company_name': '',
          'phone': digits(phone), 'phone_display': phone, 'delivery_type': city ? 'city' : 'province',
          'local_company': cell(row, 5), 'destination_address': cell(row, 6),
          'paid_by': prepaid ? '선결제' : '', 'notes': '',
          'preferred': marked.isNotEmpty || (colorPriority?.call(sheet.key, chosen) ?? 1) >= 3,
          'active': true,
        };
        block.clear();
      }
      for (var i = header + 1; i < sheet.value.length; i++) {
        final row = sheet.value[i];
        final next = int.tryParse(digits(cell(row, 0)));
        if (next != null) { flush(); number = next; }
        if (number != null && row.take(8).any((c) => c.trim().isNotEmpty)) block.add(i);
      }
      flush();
    }
    return result.values.toList();
  }

  static List<Map<String, dynamic>>? shares(Map<String, List<List<String>>> workbook) {
    final sheets = workbook.entries.where((e) => key(e.key) == '명세서선공유').toList();
    if (sheets.isEmpty) return null;
    final rows = sheets.first.value;
    final header = rows.indexWhere((r) => ['name', '이름', '고객명'].contains(key(cell(r, 1))) && ['tel', 'phone', '전화번호', '연락처'].contains(key(cell(r, 2))));
    if (header < 0) throw StateError('명세서 선공유: Name/Tel 제목 행을 확인하세요.');
    final result = <Map<String, dynamic>>[];
    for (final row in rows.skip(header + 1)) {
      final name = cell(row, 1), phone = cell(row, 2), content = cell(row, 3);
      if (name.isEmpty || digits(phone).isEmpty) continue;
      result.add({'source_no': result.length + 1, 'customer_name': name, 'phone': digits(phone), 'phone_display': phone, 'content': content.isEmpty ? '카톡 명세서 선공유' : content});
    }
    return result;
  }
}
