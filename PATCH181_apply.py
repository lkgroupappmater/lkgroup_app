from pathlib import Path

p = Path("lib/screens/statement_preview_dialog.dart")
s = p.read_text(encoding="utf-8-sig")

old = """    final discountLabel = actualDiscountPctText.isEmpty
        ? '할인'
        : '할인 $actualDiscountPctText';
    final isSpecialDiscount = discountGroupText.contains('특별');
    final regularDiscountUsd =
        isSpecialDiscount ? 0.0 : totalDiscountUsd;
    final specialDiscountUsd =
        isSpecialDiscount ? totalDiscountUsd : 0.0;

    _text(
      c,
      discountLabel,
      Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .52, adjH),
      15,
      bold: true,
    );
    _text(
      c,
      regularDiscountUsd > 0
          ? '-${MoneyFormat.usd(regularDiscountUsd)}'
          : '-',
      Rect.fromLTWH(totalX + totalW * .56, sumTop + 7, totalW * .40, adjH),
      16,
      bold: true,
      right: true,
    );
    _text(
      c,
      isSpecialDiscount && actualDiscountPctText.isNotEmpty
          ? '$discountGroupText $actualDiscountPctText'
          : '특별할인',
      Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .52, adjH),
      15,
      bold: true,
    );"""

new = """    final isSpecialDiscount = discountGroupText.contains('특별');
    final regularDiscountUsd =
        isSpecialDiscount ? 0.0 : totalDiscountUsd;
    final specialDiscountUsd =
        isSpecialDiscount ? totalDiscountUsd : 0.0;

    String discountValueText({
      required bool active,
      required double amountUsd,
    }) {
      if (!active || actualDiscountPctText.isEmpty) return '-';
      return '$actualDiscountPctText  -${MoneyFormat.usd(amountUsd)}';
    }

    _text(
      c,
      '할인',
      Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .42, adjH),
      15,
      bold: true,
    );
    _text(
      c,
      discountValueText(
        active: !isSpecialDiscount && actualDiscountPctText.isNotEmpty,
        amountUsd: regularDiscountUsd,
      ),
      Rect.fromLTWH(totalX + totalW * .42, sumTop + 7, totalW * .54, adjH),
      15,
      bold: true,
      right: true,
    );
    _text(
      c,
      '특별할인',
      Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .42, adjH),
      15,
      bold: true,
    );"""

if old not in s:
    raise SystemExit("Patch181 discount row anchor not found")

s = s.replace(old, new, 1)

old2 = """    _text(
      c,
      specialDiscountUsd > 0
          ? '-${MoneyFormat.usd(specialDiscountUsd)}'
          : '-',
      Rect.fromLTWH(totalX + totalW * .56, sumTop + 34, totalW * .40, adjH),
      16,
      bold: true,
      right: true,
    );"""

new2 = """    _text(
      c,
      discountValueText(
        active: isSpecialDiscount && actualDiscountPctText.isNotEmpty,
        amountUsd: specialDiscountUsd,
      ),
      Rect.fromLTWH(totalX + totalW * .42, sumTop + 34, totalW * .54, adjH),
      15,
      bold: true,
      right: true,
    );"""

if old2 not in s:
    raise SystemExit("Patch181 special discount value anchor not found")

s = s.replace(old2, new2, 1)

p.write_text(s, encoding="utf-8")
print("Patch181 applied.")
