from pathlib import Path

R=Path.cwd()

def load(rel):
    p=R/rel
    if not p.exists():
        raise SystemExit(f"missing: {rel}")
    return p, p.read_text(encoding="utf-8-sig")

def save(p,s):
    p.write_text(s, encoding="utf-8")

# 1) Unloading PDF: manual uncertainty -> yellow; locked remains excluded.
p,s=load("lib/screens/unloading_list_management_screen.dart")
old='''  bool _needsAttention(Map<String, dynamic> row) {
    if (row['data_locked'] == true) return false;

    final name ='''
new='''  bool _needsAttention(Map<String, dynamic> row) {
    // Locked cargo is never highlighted.
    if (row['data_locked'] == true) return false;

    // Manual ? uncertainty uses the same yellow highlight as auto uncertainty.
    if (row['manual_uncertain'] == true) return true;

    final name ='''
if old in s:
    s=s.replace(old,new,1)
elif "if (row['manual_uncertain'] == true) return true;" not in s:
    raise SystemExit("unloading _needsAttention anchor missing")
save(p,s)

# 2) Freight check / quotation request: manual percent discount.
p,s=load("lib/screens/quote_request_screen.dart")

a='''  final List<ExtraCostItem> _extraCosts = <ExtraCostItem>[];
  QuoteFreightResult? _calculation;'''
b='''  final List<ExtraCostItem> _extraCosts = <ExtraCostItem>[];
  double _manualDiscountPercent = 0;
  QuoteFreightResult? _calculation;'''
if a in s:
    s=s.replace(a,b,1)
elif "_manualDiscountPercent" not in s:
    raise SystemExit("quote state anchor missing")

anchor="  Future<void> _addQuoteExtraCost() async {"
method='''  Future<void> _setQuoteDiscountPercent() async {
    final controller = TextEditingController(
      text: _manualDiscountPercent == 0
          ? ''
          : _manualDiscountPercent.toStringAsFixed(
              _manualDiscountPercent == _manualDiscountPercent.roundToDouble()
                  ? 0
                  : 1,
            ),
    );
    final apply = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('할인율 적용'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\\d.]')),
              ],
              decoration: const InputDecoration(
                labelText: '할인율 (%)',
                hintText: '예: 20',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  controller.text = '0';
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('할인 해제'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('적용'),
              ),
            ],
          ),
        ) ??
        false;

    if (apply && mounted) {
      final value = double.tryParse(controller.text.trim()) ?? 0;
      if (value < 0 || value > 100) {
        _message('할인율은 0~100% 범위로 입력해 주세요.');
      } else {
        setState(() => _manualDiscountPercent = value);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
  }

'''
if anchor in s and "Future<void> _setQuoteDiscountPercent()" not in s:
    s=s.replace(anchor,method+anchor,1)

old='''          OutlinedButton.icon(
            onPressed: _addQuoteExtraCost,
            icon: const Icon(Icons.add_card_outlined, size: 18),
            label: const Text('기타 비용 추가 (+\\$)',
                style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navyPrimary,
              side: const BorderSide(color: AppColors.navyPrimary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),'''
new='''          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addQuoteExtraCost,
                  icon: const Icon(Icons.add_card_outlined, size: 18),
                  label: const Text(
                    '기타 비용 추가 (+\\$)',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navyPrimary,
                    side: const BorderSide(color: AppColors.navyPrimary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _setQuoteDiscountPercent,
                  icon: const Icon(Icons.percent, size: 18),
                  label: Text(
                    _manualDiscountPercent > 0
                        ? '할인 ${_manualDiscountPercent.toStringAsFixed(_manualDiscountPercent == _manualDiscountPercent.roundToDouble() ? 0 : 1)}%'
                        : '할인율 (%)',
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _manualDiscountPercent > 0
                        ? Colors.deepOrange
                        : AppColors.navyPrimary,
                    side: BorderSide(
                      color: _manualDiscountPercent > 0
                          ? Colors.deepOrange
                          : AppColors.navyPrimary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),'''
if old in s:
    s=s.replace(old,new,1)
elif "'할인율 (%)'" not in s:
    raise SystemExit("quote button anchor missing")

a='''                    Text('\\$${entry.value.amountUsd.toStringAsFixed(2)}'),
                    IconButton('''
b='''                    Tooltip(
                      message: '이 기타 비용에도 현재 할인율 적용',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: entry.value.discountApplies,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) => setState(() {
                              _extraCosts[entry.key] = ExtraCostItem(
                                id: entry.value.id,
                                name: entry.value.name,
                                amountUsd: entry.value.amountUsd,
                                discountApplies: v ?? false,
                              );
                            }),
                          ),
                          const Text('할인', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                    Text('\\$${entry.value.amountUsd.toStringAsFixed(2)}'),
                    IconButton('''
if a in s:
    s=s.replace(a,b,1)
elif "이 기타 비용에도 현재 할인율 적용" not in s:
    raise SystemExit("extra cost discount checkbox anchor missing")

a='''        extraCosts: List<ExtraCostItem>.unmodifiable(_extraCosts),
      ),'''
b='''        extraCosts: List<ExtraCostItem>.unmodifiable(_extraCosts),
        discountPercent: _manualDiscountPercent,
      ),'''
if a in s:
    s=s.replace(a,b,1)
elif "discountPercent: _manualDiscountPercent" not in s:
    raise SystemExit("quotation preview call anchor missing")

a='''    final extraTotal =
        _extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final finalUsd = result.totalUsd + extraTotal;
    final kip = rates == null ? null : finalUsd * rates.appliedKip;'''
b='''    final extraTotal =
        _extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final discountableExtra = _extraCosts
        .where((e) => e.discountApplies)
        .fold<double>(0, (sum, e) => sum + e.amountUsd);
    final grossUsd = result.totalUsd + extraTotal;
    final discountBase = result.totalUsd + discountableExtra;
    final discountAmount =
        discountBase * (_manualDiscountPercent.clamp(0, 100) / 100);
    final finalUsd = grossUsd - discountAmount;
    final kip = rates == null ? null : finalUsd * rates.appliedKip;'''
if a in s:
    s=s.replace(a,b,1)
elif "final discountBase = result.totalUsd + discountableExtra;" not in s:
    raise SystemExit("freight result calculation anchor missing")

a="'기타 비용 · ${e.name}',"
b="'기타 비용 · ${e.name}${e.discountApplies && _manualDiscountPercent > 0 ? ' · 할인 적용' : ''}',"
if a in s:
    s=s.replace(a,b,1)

a='''                  Text(
                    '총 운임  USD \\$${finalUsd.toStringAsFixed(2)}',
                    style: const TextStyle('''
b='''                  if (_manualDiscountPercent > 0) ...[
                    Text(
                      '할인 전  USD \\$${grossUsd.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '할인 ${_manualDiscountPercent.toStringAsFixed(_manualDiscountPercent == _manualDiscountPercent.roundToDouble() ? 0 : 1)}%  -\\$${discountAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    '총 운임  USD \\$${finalUsd.toStringAsFixed(2)}',
                    style: const TextStyle('''
if a in s:
    s=s.replace(a,b,1)
elif "'할인 전  USD" not in s:
    raise SystemExit("freight total display anchor missing")

save(p,s)

# 3) Quotation preview/PDF uses same manual discount.
p,s=load("lib/screens/quotation_preview_dialog.dart")

pairs=[
('''    this.extraCosts = const <ExtraCostItem>[],
  });''',
 '''    this.extraCosts = const <ExtraCostItem>[],
    this.discountPercent = 0,
  });'''),
('''  final List<ExtraCostItem> extraCosts;
  @override''',
 '''  final List<ExtraCostItem> extraCosts;
  final double discountPercent;
  @override'''),
('''        extraCosts: widget.extraCosts,
        issuedAt: _issuedAt,''',
 '''        extraCosts: widget.extraCosts,
        discountPercent: widget.discountPercent,
        issuedAt: _issuedAt,'''),
('''    required this.extraCosts,
    required this.issuedAt,''',
 '''    required this.extraCosts,
    required this.discountPercent,
    required this.issuedAt,'''),
('''  final List<ExtraCostItem> extraCosts;
  final DateTime issuedAt;''',
 '''  final List<ExtraCostItem> extraCosts;
  final double discountPercent;
  final DateTime issuedAt;'''),
]
for a,b in pairs:
    if a in s:
        s=s.replace(a,b,1)

a='''    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final usd = result.totalUsd + extraTotal;
    final summaryValues = <int, String>{'''
b='''    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final discountableExtra = extraCosts
        .where((e) => e.discountApplies)
        .fold<double>(0, (sum, e) => sum + e.amountUsd);
    final grossUsd = result.totalUsd + extraTotal;
    final safeDiscountPercent = discountPercent.clamp(0, 100).toDouble();
    final discountBase = result.totalUsd + discountableExtra;
    final discountAmount = discountBase * safeDiscountPercent / 100;
    final usd = grossUsd - discountAmount;
    final summaryValues = <int, String>{'''
if a in s:
    s=s.replace(a,b,1)
elif "final safeDiscountPercent = discountPercent.clamp(0, 100).toDouble();" not in s:
    raise SystemExit("quotation calculation anchor missing")

if "13: MoneyFormat.usd(usd)," in s:
    s=s.replace("13: MoneyFormat.usd(usd),","13: MoneyFormat.usd(grossUsd),",1)

a='''    final adjH = 25.0;
    for (final row in <(String, double)>[
      ('할인', sumTop + 7),
      ('특별할인', sumTop + 34),
      ('세금 계산서(VAT)', sumTop + 61),
    ]) {
      _text(c, row.$1, Rect.fromLTWH(totalX + 12, row.$2, totalW * .48, adjH), 16, bold: true);
      _text(c, '-', Rect.fromLTWH(totalX + totalW * .58, row.$2, totalW * .18, adjH), 16, bold: true, center: true);
      _text(c, '-', Rect.fromLTWH(totalX + totalW * .78, row.$2, totalW * .18, adjH), 16, bold: true, right: true);
    }
'''
b='''    final adjH = 25.0;
    final discountLabel = safeDiscountPercent > 0
        ? '${safeDiscountPercent.toStringAsFixed(safeDiscountPercent == safeDiscountPercent.roundToDouble() ? 0 : 1)}%'
        : '-';
    final discountValue =
        safeDiscountPercent > 0 ? '-${MoneyFormat.usd(discountAmount)}' : '-';

    _text(c, '할인',
        Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .48, adjH),
        16, bold: true);
    _text(c, discountLabel,
        Rect.fromLTWH(totalX + totalW * .58, sumTop + 7, totalW * .18, adjH),
        16, bold: true, center: true);
    _text(c, discountValue,
        Rect.fromLTWH(totalX + totalW * .78, sumTop + 7, totalW * .18, adjH),
        16, bold: true, right: true);

    for (final row in <(String, double)>[
      ('특별할인', sumTop + 34),
      ('세금 계산서(VAT)', sumTop + 61),
    ]) {
      _text(c, row.$1,
          Rect.fromLTWH(totalX + 12, row.$2, totalW * .48, adjH),
          16, bold: true);
      _text(c, '-',
          Rect.fromLTWH(totalX + totalW * .58, row.$2, totalW * .18, adjH),
          16, bold: true, center: true);
      _text(c, '-',
          Rect.fromLTWH(totalX + totalW * .78, row.$2, totalW * .18, adjH),
          16, bold: true, right: true);
    }
'''
if a in s:
    s=s.replace(a,b,1)
elif "final discountLabel = safeDiscountPercent > 0" not in s:
    raise SystemExit("quotation adjustment anchor missing")

a='''          extra.name,
          Rect.fromLTRB(cols[1] + 3'''
b='''          '${extra.name}${extra.discountApplies && safeDiscountPercent > 0 ? ' (할인)' : ''}',
          Rect.fromLTRB(cols[1] + 3'''
if a in s:
    s=s.replace(a,b,1)

save(p,s)

checks=[]
u=(R/"lib/screens/unloading_list_management_screen.dart").read_text(encoding="utf-8")
checks.append(("unloading manual yellow","if (row['manual_uncertain'] == true) return true;" in u))
checks.append(("unloading lock priority",u.find("data_locked") < u.find("manual_uncertain")))
u=(R/"lib/screens/quote_request_screen.dart").read_text(encoding="utf-8")
checks.append(("freight discount button","Future<void> _setQuoteDiscountPercent()" in u and "'할인율 (%)'" in u))
checks.append(("extra discount checkbox","이 기타 비용에도 현재 할인율 적용" in u))
checks.append(("freight discount math","final discountBase = result.totalUsd + discountableExtra;" in u))
checks.append(("preview discount pass","discountPercent: _manualDiscountPercent" in u))
u=(R/"lib/screens/quotation_preview_dialog.dart").read_text(encoding="utf-8")
checks.append(("quotation discount field","final double discountPercent;" in u))
checks.append(("quotation adjusted final","final usd = grossUsd - discountAmount;" in u))
checks.append(("quotation discount row","final discountLabel = safeDiscountPercent > 0" in u))

print("PATCH195 VERIFY")
bad=[]
for name,ok in checks:
    print(("[OK] " if ok else "[FAIL] ")+name)
    if not ok: bad.append(name)
if bad:
    raise SystemExit("VERIFY FAILED: "+", ".join(bad))
print("PATCH195 VERIFIED OK")
