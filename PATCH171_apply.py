from pathlib import Path
p=Path.cwd()/"lib"/"screens"/"statement_preview_dialog.dart"
if not p.exists(): raise SystemExit("statement_preview_dialog.dart not found")
s=p.read_text(encoding="utf-8-sig")
old="""    _text(c, 'Inland delivery/시내·지방 배송',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 7, leftW * .42 - 24, 24),
        18, bold: true);
    _text(
      c,
      inlandDeliveryText,
      Rect.fromLTWH(leftW * .58 + 14, sumTop + 38, leftW * .42 - 24, 112),
      15.5,
      maxLines: 5,
      lineHeight: 1.12,
    );"""
new="""    _text(c, 'Inland delivery/시내·지방 배송',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 7, leftW * .42 - 24, 24),
        18, bold: true);

    final deliveryNote = rows
        .map((e) => '${e['special_note_auto'] ?? e['special_note'] ?? ''}')
        .join(' ');
    Color? deliveryColor;
    if (deliveryNote.contains('지방배송(선결제)')) {
      deliveryColor = const Color(0xFF5B9BD5);
    } else if (deliveryNote.contains('시내배송(선결제)')) {
      deliveryColor = const Color(0xFFFFFF00);
    } else if (deliveryNote.contains('지방배송')) {
      deliveryColor = const Color(0xFFFFC000);
    } else if (deliveryNote.contains('시내배송')) {
      deliveryColor = const Color(0xFF92D050);
    }
    if (deliveryColor != null && inlandDeliveryText.trim().isNotEmpty) {
      c.drawRect(
        Rect.fromLTWH(leftW * .58 + 8, sumTop + 34, leftW * .42 - 16, 118),
        Paint()..color = deliveryColor.withOpacity(.32),
      );
    }
    _text(
      c,
      inlandDeliveryText,
      Rect.fromLTWH(leftW * .58 + 14, sumTop + 40, leftW * .42 - 24, 108),
      18.5,
      bold: true,
      center: true,
      maxLines: 5,
      lineHeight: 1.16,
    );"""
if s.count(old)!=1: raise SystemExit(f"statement anchor expected 1, found {s.count(old)}")
p.write_text(s.replace(old,new,1),encoding="utf-8")
print("Patch171 Dart applied.")
