from pathlib import Path
p=Path("lib/screens/statement_preview_dialog.dart")
s=p.read_text(encoding="utf-8-sig")

bad="""      displayAutoNotes = displayAutoNotes.replaceFirst(
        RegExp(r'(^| / )할인\\s+([0-9.]+% 적용)'),
        (m) => '${m.group(1) ?? ''}$group 할인 ${m.group(2)}',
      );"""
good="""      final genericDiscount = RegExp(r'(^| / )할인\\s+([0-9.]+% 적용)');
      final match = genericDiscount.firstMatch(displayAutoNotes);
      if (match != null) {
        final replacement =
            '${match.group(1) ?? ''}$group 할인 ${match.group(2) ?? ''}';
        displayAutoNotes = displayAutoNotes.replaceRange(
          match.start,
          match.end,
          replacement,
        );
      }"""
if bad not in s:
    raise SystemExit("Patch176 오류 구문을 찾지 못했습니다. 현재 파일을 확인해 주세요.")
s=s.replace(bad,good,1)
p.write_text(s,encoding="utf-8")
print("Patch176B compile hotfix applied.")
