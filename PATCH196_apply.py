from pathlib import Path
import re

R = Path.cwd()

def read(rel):
    p = R / rel
    if not p.exists():
        raise SystemExit(f"missing: {rel}")
    return p, p.read_text(encoding="utf-8-sig")

def write(p, s):
    p.write_text(s, encoding="utf-8")

# ============================================================
# 1) Statement: discount checked extra-costs even when freight=0
# ============================================================
p, s = read("lib/screens/statement_preview_dialog.dart")

old = """    final baseDiscountPercent = freight.grossTotalUsd <= 0
        ? 0.0
        : (freight.discountTotalUsd / freight.grossTotalUsd)
            .clamp(0.0, 1.0);
    final discountableExtraTotal = extraCosts
"""
new = """    // Use the actual discount rule from FreightService lines first.
    // Important: when freight is $0, gross/discount ratio is 0/0-ish and
    // previously made a checked extra cost receive no discount at all.
    final lineBaseDiscountPercent = freight.lines
        .map((line) => line.discountPercent)
        .fold<double>(0, (best, value) => value > best ? value : best);
    final baseDiscountPercent = lineBaseDiscountPercent > 0
        ? lineBaseDiscountPercent
        : (freight.grossTotalUsd <= 0
            ? 0.0
            : (freight.discountTotalUsd / freight.grossTotalUsd)
                .clamp(0.0, 1.0));
    final discountableExtraTotal = extraCosts
"""
if old in s:
    s = s.replace(old, new, 1)
elif "final lineBaseDiscountPercent = freight.lines" not in s:
    raise SystemExit("statement discount anchor missing")

write(p, s)

# ============================================================
# 2) Unloading PDF:
#    - robust manual_uncertain merge even if RPC omits the column
#    - F/Y-style switch for locked cargo yellow highlighting
# ============================================================
p, s = read("lib/screens/unloading_list_management_screen.dart")

# Supabase import for direct manual_uncertain IDs.
imp = "import 'package:pdf/widgets.dart' as pw;\n"
if "package:supabase_flutter/supabase_flutter.dart" not in s:
    if imp not in s:
        raise SystemExit("unloading import anchor missing")
    s = s.replace(
        imp,
        imp + "import 'package:supabase_flutter/supabase_flutter.dart';\n",
        1,
    )

# State flag: default YES per user's request, but can be turned off.
anchor = """  bool _busy = true;
  bool _saving = false;
"""
replacement = """  bool _busy = true;
  bool _saving = false;
  bool _highlightLocked = true;
"""
if anchor in s:
    s = s.replace(anchor, replacement, 1)
elif "_highlightLocked" not in s:
    raise SystemExit("unloading state anchor missing")

# Replace _loadRows body with robust enrichment.
old_load = """      final rows = await ExcelBulkManagementService.instance.listRows(
        route: _route!,
        year: _year!,
        voyage: _voyage!,
      );
      rows.sort((a, b) => _boxOrder(a).compareTo(_boxOrder(b)));
"""
new_load = """      final rows = await ExcelBulkManagementService.instance.listRows(
        route: _route!,
        year: _year!,
        voyage: _voyage!,
      );

      // admin_excel_bulk_rows may not expose the Patch194 manual_uncertain
      // column. Enrich it directly from shipments so ? always reaches PDF.
      try {
        final manualRaw = await Supabase.instance.client
            .from('shipments')
            .select('id')
            .eq('manual_uncertain', true);
        final manualIds = List<Map<String, dynamic>>.from(manualRaw as List)
            .map((e) => '${e['id'] ?? ''}')
            .where((e) => e.isNotEmpty)
            .toSet();
        for (final row in rows) {
          if (manualIds.contains('${row['id'] ?? ''}')) {
            row['manual_uncertain'] = true;
          }
        }
      } catch (_) {
        // Keep existing RPC data if direct enrichment is unavailable.
      }

      rows.sort((a, b) => _boxOrder(a).compareTo(_boxOrder(b)));
"""
if old_load in s:
    s = s.replace(old_load, new_load, 1)
elif "admin_excel_bulk_rows may not expose" not in s:
    raise SystemExit("unloading loadRows anchor missing")

# Replace attention semantics. Locked yellow is switchable.
pattern = re.compile(
    r"""  bool _needsAttention\(Map<String, dynamic> row\) \{
(?:.|\n)*?
    final name =""",
    re.MULTILINE,
)
m = pattern.search(s)
if not m:
    raise SystemExit("unloading needsAttention function anchor missing")
prefix = """  bool _needsAttention(Map<String, dynamic> row) {
    final locked = row['data_locked'] == true;

    // F/Y option: when ON, every locked cargo is yellow in unloading PDF.
    // When OFF, locked cargo is excluded from yellow as in the old rule.
    if (locked) return _highlightLocked;

    // Manual ? uncertainty is yellow regardless of auto-detection.
    if (row['manual_uncertain'] == true) return true;

    final name ="""
s = s[:m.start()] + prefix + s[m.end():]

# Add SwitchListTile before status line.
status_anchor = """            if (!_busy && _voyage != null)
              Text(
                '화물 ${_rows.length}건 · 노란색 확인 필요 ${_rows.where(_needsAttention).length}건',
              ),
"""
status_new = """            if (!_busy && _voyage != null) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  '잠금 물품 노란색 표시',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _highlightLocked ? 'Y · 잠금 화물도 노란색' : 'F · 잠금 화물은 노란색 제외',
                  style: const TextStyle(fontSize: 11),
                ),
                value: _highlightLocked,
                onChanged: (v) => setState(() => _highlightLocked = v),
              ),
              Text(
                '화물 ${_rows.length}건 · 노란색 확인 필요 ${_rows.where(_needsAttention).length}건',
              ),
            ],
"""
if status_anchor in s:
    s = s.replace(status_anchor, status_new, 1)
elif "'잠금 물품 노란색 표시'" not in s:
    raise SystemExit("unloading status UI anchor missing")

# Update old explanatory note, if present.
old_note = """              '관리자가 확인 후 잠금한 화물은 노란색에서 제외됩니다.',"""
new_note = """              '수동 ? 표시 화물은 노란색으로 표시되며, 잠금 화물의 노란색 표시는 위 F/Y 스위치로 선택할 수 있습니다.',"""
if old_note in s:
    s = s.replace(old_note, new_note, 1)

write(p, s)

# ============================================================
# VERIFY
# ============================================================
checks = []

u = (R / "lib/screens/statement_preview_dialog.dart").read_text(encoding="utf-8")
checks += [
    ("statement line discount source",
     "final lineBaseDiscountPercent = freight.lines" in u),
    ("statement checked extras use percent",
     "final extraDiscountUsd =" in u and
     "discountableExtraTotal * baseDiscountPercent" in u),
]

u = (R / "lib/screens/unloading_list_management_screen.dart").read_text(encoding="utf-8")
checks += [
    ("unloading manual direct enrichment",
     ".eq('manual_uncertain', true)" in u),
    ("locked F/Y switch",
     "_highlightLocked = true" in u and "'잠금 물품 노란색 표시'" in u),
    ("locked attention switch semantics",
     "if (locked) return _highlightLocked;" in u),
    ("manual uncertain yellow",
     "if (row['manual_uncertain'] == true) return true;" in u),
]

print("PATCH196 VERIFY")
bad = []
for name, ok in checks:
    print(("[OK] " if ok else "[FAIL] ") + name)
    if not ok:
        bad.append(name)

if bad:
    raise SystemExit("VERIFY FAILED: " + ", ".join(bad))

print("PATCH196 VERIFIED OK")
