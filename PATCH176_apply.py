from pathlib import Path
cwd = Path.cwd()

def rd(p):
    return p.read_text(encoding="utf-8-sig")

def wr(p, s):
    p.write_text(s, encoding="utf-8")

# ------------------------------------------------------------
# 1) Extra cost model/service: discount checkbox
# ------------------------------------------------------------
p = cwd / "lib/services/receipt_extra_cost_service.dart"
s = rd(p)

s = s.replace(
"""  const ExtraCostItem({
    this.id,
    required this.name,
    required this.amountUsd,
  });""",
"""  const ExtraCostItem({
    this.id,
    required this.name,
    required this.amountUsd,
    this.discountApplies = false,
  });""",
1)

s = s.replace(
"""  final String name;
  final double amountUsd;""",
"""  final String name;
  final double amountUsd;
  final bool discountApplies;""",
1)

s = s.replace(
"""        amountUsd:
            double.tryParse('${row['amount_usd'] ?? row['amount'] ?? 0}') ?? 0,
      );""",
"""        amountUsd:
            double.tryParse('${row['amount_usd'] ?? row['amount'] ?? 0}') ?? 0,
        discountApplies: row['discount_applies'] == true,
      );""",
1)

s = s.replace(
"""    required String name,
    required double amountUsd,
  }) async {""",
"""    required String name,
    required double amountUsd,
    bool discountApplies = false,
  }) async {""",
1)

s = s.replace(
"""        'p_cost_name': name.trim(),
        'p_amount_usd': amountUsd,
      },""",
"""        'p_cost_name': name.trim(),
        'p_amount_usd': amountUsd,
        'p_discount_applies': discountApplies,
      },""",
1)

wr(p, s)

# ------------------------------------------------------------
# 2) Cargo management: checkbox UI, default OFF
# ------------------------------------------------------------
p = cwd / "lib/screens/cargo_management_screen.dart"
s = rd(p)

s = s.replace(
"""    final name = TextEditingController();
    final amount = TextEditingController();
    int? editingId;""",
"""    final name = TextEditingController();
    final amount = TextEditingController();
    int? editingId;
    var discountApplies = false;""",
1)

s = s.replace(
"""                                  name.text = e.name;
                                  amount.text = e.amountUsd.toStringAsFixed(2);""",
"""                                  name.text = e.name;
                                  amount.text = e.amountUsd.toStringAsFixed(2);
                                  setDialogState(
                                    () => discountApplies = e.discountApplies,
                                  );""",
1)

s = s.replace(
"""                          subtitle: Text('\\$${e.amountUsd.toStringAsFixed(2)}'),""",
"""                          subtitle: Text(
                            '\\$${e.amountUsd.toStringAsFixed(2)}'
                            '${e.discountApplies ? ' · 할인 적용' : ''}',
                          ),""",
1)

checkbox_anchor = """                    TextField(
                      controller: amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '금액 (USD)',
                        prefixText: '\\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),"""
checkbox_repl = checkbox_anchor + """
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: discountApplies,
                      title: const Text('할인 적용'),
                      subtitle: const Text(
                        '체크 시 해당 고객의 할인율을 이 기타 비용에도 적용합니다. '
                        '기본은 미체크입니다.',
                      ),
                      onChanged: (v) => setDialogState(
                        () => discountApplies = v == true,
                      ),
                    ),"""
if checkbox_anchor in s and "체크 시 해당 고객의 할인율" not in s:
    s = s.replace(checkbox_anchor, checkbox_repl, 1)

s = s.replace(
"""                    name: name.text,
                    amountUsd: value,
                  );
                  name.clear();
                  amount.clear();
                  setDialogState(() => editingId = null);""",
"""                    name: name.text,
                    amountUsd: value,
                    discountApplies: discountApplies,
                  );
                  name.clear();
                  amount.clear();
                  setDialogState(() {
                    editingId = null;
                    discountApplies = false;
                  });""",
1)

wr(p, s)

# ------------------------------------------------------------
# 3) Statement preview:
#    gross line items -> discount panel deducts -> final total
#    Remark centered
# ------------------------------------------------------------
p = cwd / "lib/screens/statement_preview_dialog.dart"
s = rd(p)

# Extra row label
s = s.replace(
"""          extra.name,
          Rect.fromLTRB(cols[1] + 3, y + 2, cols[2] - 3, y + rowH - 2),""",
"""          extra.discountApplies ? '${extra.name} (할인)' : extra.name,
          Rect.fromLTRB(cols[1] + 3, y + 2, cols[2] - 3, y + rowH - 2),""",
1)

# Claimed freight amount: show gross in table, then deduct in summary panel.
s = s.replace(
"""        f == null ? '-' : MoneyFormat.usd(f.amountUsd),""",
"""        f == null ? '-' : MoneyFormat.usd(f.grossAmountUsd),""",
1)

old_totals = """    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);

    final finalUsd = freight.totalUsd + extraTotal;"""
new_totals = """    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final baseDiscountPercent = freight.grossTotalUsd <= 0
        ? 0.0
        : (freight.discountTotalUsd / freight.grossTotalUsd)
            .clamp(0.0, 1.0);
    final discountableExtraTotal = extraCosts
        .where((e) => e.discountApplies)
        .fold<double>(0, (sum, e) => sum + e.amountUsd);
    final extraDiscountUsd =
        discountableExtraTotal * baseDiscountPercent;
    final totalDiscountUsd =
        freight.discountTotalUsd + extraDiscountUsd;
    final finalUsd =
        freight.grossTotalUsd + extraTotal - totalDiscountUsd;"""
if old_totals not in s:
    raise SystemExit("statement total anchor not found")
s = s.replace(old_totals, new_totals, 1)

# Remark: enrich generic discount wording from FreightService group where possible.
old_remark = """    final remarkText = autoNotes.isEmpty
        ? docText.remark
        : '${docText.remark}\\n\\n$autoNotes';
    _text(c, remarkText,
        Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),
        docText.remarkFontSize, maxLines: 6, lineHeight: 1.05);"""
new_remark = """    final freightGroups = freight.lines
        .map((line) => line.discountGroup.trim())
        .where((value) => value.isNotEmpty && value != '기타 할인')
        .toSet()
        .toList(growable: false);
    var displayAutoNotes = autoNotes;
    if (freightGroups.length == 1 &&
        displayAutoNotes.contains(RegExp(r'(^| / )할인\\s+[0-9.]+% 적용'))) {
      final group = freightGroups.first;
      displayAutoNotes = displayAutoNotes.replaceFirst(
        RegExp(r'(^| / )할인\\s+([0-9.]+% 적용)'),
        (m) => '${m.group(1) ?? ''}$group 할인 ${m.group(2)}',
      );
    }
    final remarkText = displayAutoNotes.isEmpty
        ? docText.remark
        : '${docText.remark}\\n\\n$displayAutoNotes';
    _text(
      c,
      remarkText,
      Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),
      docText.remarkFontSize,
      bold: true,
      center: true,
      maxLines: 6,
      lineHeight: 1.05,
    );"""
if old_remark not in s:
    raise SystemExit("remark anchor not found")
s = s.replace(old_remark, new_remark, 1)

old_panel = """    _text(c, '할인', Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .46, adjH), 16, bold: true);
    _text(c, freight.discountTotalUsd > 0 ? '-${MoneyFormat.usd(freight.discountTotalUsd)}' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 7, totalW * .44, adjH), 16, bold: true, right: true);
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
    _text(c, '세금 계산서(VAT)', Rect.fromLTWH(totalX + 12, sumTop + 61, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 61, totalW * .44, adjH), 16, bold: true, right: true);"""
new_panel = """    final discountPercentText = baseDiscountPercent > 0
        ? '${(baseDiscountPercent * 100).toStringAsFixed(
            ((baseDiscountPercent * 100) -
                        (baseDiscountPercent * 100).roundToDouble())
                    .abs() <
                .001
                ? 0
                : 2,
          )}%'
        : '';
    final discountGroupText = freight.lines
        .map((line) => line.discountGroup.trim())
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );
    final isSpecialDiscount = discountGroupText.contains('특별');
    final regularDiscountUsd =
        isSpecialDiscount ? 0.0 : totalDiscountUsd;
    final specialDiscountUsd =
        isSpecialDiscount ? totalDiscountUsd : 0.0;

    _text(
      c,
      discountPercentText.isEmpty ? '할인' : '할인 $discountPercentText',
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
      discountPercentText.isEmpty
          ? '특별할인'
          : '특별할인 $discountPercentText',
      Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .52, adjH),
      15,
      bold: true,
    );
    _text(
      c,
      specialDiscountUsd > 0
          ? '-${MoneyFormat.usd(specialDiscountUsd)}'
          : '-',
      Rect.fromLTWH(totalX + totalW * .56, sumTop + 34, totalW * .40, adjH),
      16,
      bold: true,
      right: true,
    );
    _text(c, '세금 계산서(VAT)', Rect.fromLTWH(totalX + 12, sumTop + 61, totalW * .52, adjH), 15, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .56, sumTop + 61, totalW * .40, adjH), 16, bold: true, right: true);"""
if old_panel not in s:
    raise SystemExit("discount panel anchor not found")
s = s.replace(old_panel, new_panel, 1)

wr(p, s)

# ------------------------------------------------------------
# 4) Unloading PDF: 404 rows => 2 pages, smaller cells
# ------------------------------------------------------------
p = cwd / "lib/screens/unloading_list_management_screen.dart"
s = rd(p)
s = s.replace("const rowsPerColumn = 27;", "const rowsPerColumn = 34;", 1)
s = s.replace("const groups = 5;", "const groups = 6;", 1)
s = s.replace("margin: const pw.EdgeInsets.all(18),", "margin: const pw.EdgeInsets.all(12),", 1)
s = s.replace("pw.SizedBox(height: 8),", "pw.SizedBox(height: 5),", 1)
s = s.replace("right: group == groups - 1 ? 0 : 5,", "right: group == groups - 1 ? 0 : 3,", 1)
s = s.replace("height: 18.2,", "height: 14.0,", 1)
s = s.replace("fontSize: 8.5,", "fontSize: 7.5,", 1)
wr(p, s)

# ------------------------------------------------------------
# 5) Edge Excel exporter: discounted extra costs affect final helper amount.
# ------------------------------------------------------------
p = cwd / "supabase/functions/export-shipment-excel/index.ts"
s = rd(p)

s = s.replace(
""".select('voyage,receipt_number,cost_name,amount_usd')""",
""".select('voyage,receipt_number,cost_name,amount_usd,discount_applies')""",
1)

old_extra = """  const receiptAmounts = new Map<string, number>();
  const rawReceipts = Array.isArray(settlement?.receipts) ? settlement!.receipts as Record<string, unknown>[] : [];
  for (const r of rawReceipts) receiptAmounts.set(String(r.receipt_number ?? '').trim(), Number(r.net_usd ?? 0));
  const extraMap = new Map<string, number>();
  for (const e of extraCosts) {
    const receipt = String(e.receipt_number ?? '').trim();
    extraMap.set(receipt, (extraMap.get(receipt) ?? 0) + Number(e.amount_usd ?? 0));
  }"""
new_extra = """  const receiptAmounts = new Map<string, number>();
  const receiptDiscountRates = new Map<string, number>();
  const rawReceipts = Array.isArray(settlement?.receipts) ? settlement!.receipts as Record<string, unknown>[] : [];
  for (const r of rawReceipts) {
    const receipt = String(r.receipt_number ?? '').trim();
    const gross = Number(r.gross_usd ?? 0);
    const discount = Number(r.discount_usd ?? 0);
    receiptAmounts.set(receipt, Number(r.net_usd ?? 0));
    receiptDiscountRates.set(
      receipt,
      gross > 0 ? Math.max(0, Math.min(1, discount / gross)) : 0,
    );
  }
  const extraMap = new Map<string, number>();
  const discountedExtraMap = new Map<string, number>();
  for (const e of extraCosts) {
    const receipt = String(e.receipt_number ?? '').trim();
    const amount = Number(e.amount_usd ?? 0);
    extraMap.set(receipt, (extraMap.get(receipt) ?? 0) + amount);
    if (e.discount_applies === true) {
      discountedExtraMap.set(
        receipt,
        (discountedExtraMap.get(receipt) ?? 0) + amount,
      );
    }
  }"""
if old_extra not in s:
    raise SystemExit("edge extra map anchor not found")
s = s.replace(old_extra, new_extra, 1)

old_final = """    const extra = extraMap.get(receipt) ?? 0;
    add([receipt,name,phone,auto,delivery,type,extra,(receiptAmounts.get(receipt) ?? 0) + extra]);"""
new_final = """    const extra = extraMap.get(receipt) ?? 0;
    const discountRate = receiptDiscountRates.get(receipt) ?? 0;
    const extraDiscount =
      (discountedExtraMap.get(receipt) ?? 0) * discountRate;
    add([
      receipt,
      name,
      phone,
      auto,
      delivery,
      type,
      extra,
      (receiptAmounts.get(receipt) ?? 0) + extra - extraDiscount,
    ]);"""
if old_final not in s:
    raise SystemExit("edge final amount anchor not found")
s = s.replace(old_final, new_final, 1)

wr(p, s)

print("Patch176 applied.")
