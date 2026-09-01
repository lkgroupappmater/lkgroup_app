from pathlib import Path

cwd = Path.cwd()

# 1) FreightService: remove any Park-specific forced discount.
p = cwd / "lib/services/freight_service.dart"
s = p.read_text(encoding="utf-8-sig")

forced = """      final isParkSeongho = _isParkSeongho(name);
      final discount = isParkSeongho
          ? 1.0
          : _d(override?['discount_percent']).clamp(0, 1).toDouble();
      final discountAmount = grossAmount * discount;
      final amount = grossAmount - discountAmount;
      final group = isParkSeongho
          ? '특별할인'
          : '${override?['group_name'] ?? ''}'.trim();"""
normal = """      final discount =
          _d(override?['discount_percent']).clamp(0, 1).toDouble();
      final discountAmount = grossAmount * discount;
      final amount = grossAmount - discountAmount;
      final group = '${override?['group_name'] ?? ''}'.trim();"""
if forced in s:
    s = s.replace(forced, normal, 1)

helper = """  static bool _isParkSeongho(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[\\\\s/,_()\\\\-]+'), '')
        .toLowerCase();
    return normalized.startsWith('박성호');
  }

"""
if helper in s:
    s = s.replace(helper, "", 1)

p.write_text(s, encoding="utf-8")

# 2) Statement: remove Park-specific suppression. Discount display must be
# entirely driven by FreightService/customer discount chart.
p = cwd / "lib/screens/statement_preview_dialog.dart"
s = p.read_text(encoding="utf-8-sig")

park_block = """    final isParkSeonghoReceipt = rows.any((row) {
      final name = '${row['consignee_name'] ?? ''}'
          .replaceAll(RegExp(r'[\\\\s/,_()\\\\-]+'), '')
          .toLowerCase();
      final receipt = '${row['receipt_number'] ?? ''}'.trim().toUpperCase();
      return name.startsWith('박성호') || receipt == 'LKS 100';
    });

    var displayAutoNotes = autoNotes;
    if (freightDiscountPercent > 0 && !isParkSeonghoReceipt) {"""
normal_block = """    var displayAutoNotes = autoNotes;
    if (freightDiscountPercent > 0) {"""
if park_block in s:
    s = s.replace(park_block, normal_block, 1)

p.write_text(s, encoding="utf-8")

print("Patch182R applied: no person-specific fixed discount remains.")
