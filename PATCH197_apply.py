from pathlib import Path
import re

R = Path.cwd()
p = R / "lib/screens/statement_preview_dialog.dart"
if not p.exists():
    raise SystemExit("missing: lib/screens/statement_preview_dialog.dart")

s = p.read_text(encoding="utf-8-sig")

# 1) Pass voyage into the painter.
old = """        freight: _freight!,
        receiptNumber: widget.receiptNumber,
        arrivalDate: _arrivalDate,"""
new = """        freight: _freight!,
        receiptNumber: widget.receiptNumber,
        voyage: widget.voyage,
        arrivalDate: _arrivalDate,"""
if old in s:
    s = s.replace(old, new, 1)
elif "voyage: widget.voyage," not in s:
    raise SystemExit("painter call anchor missing")

# 2) Painter constructor.
old = """    required this.freight,
    required this.receiptNumber,
    required this.arrivalDate,"""
new = """    required this.freight,
    required this.receiptNumber,
    required this.voyage,
    required this.arrivalDate,"""
if old in s:
    s = s.replace(old, new, 1)
elif "required this.voyage," not in s:
    raise SystemExit("painter constructor anchor missing")

# 3) Painter field.
old = """  final FreightCalculation freight;
  final String receiptNumber;
  final String? arrivalDate;"""
new = """  final FreightCalculation freight;
  final String receiptNumber;
  final String voyage;
  final String? arrivalDate;"""
if old in s:
    s = s.replace(old, new, 1)
elif "final String voyage;" not in s:
    raise SystemExit("painter field anchor missing")

# 4) Normalize voyage label and add to the main document title.
# Avoid duplicate '항차' if DB voyage already contains it.
old_title = """    _text(c, '${RouteCatalog.documentTitleFor(routeLabel)} 거래 명세서',
        Rect.fromLTWH(0, 12, w, 62),"""
new_title = """    final voyageText = voyage.trim().isEmpty
        ? ''
        : (voyage.trim().endsWith('항차') ? voyage.trim() : '${voyage.trim()}항차');
    final statementTitle = voyageText.isEmpty
        ? '${RouteCatalog.documentTitleFor(routeLabel)} 거래 명세서'
        : '${RouteCatalog.documentTitleFor(routeLabel)} $voyageText 거래 명세서';

    _text(c, statementTitle,
        Rect.fromLTWH(0, 12, w, 62),"""
if old_title in s:
    s = s.replace(old_title, new_title, 1)
elif "final statementTitle = voyageText.isEmpty" not in s:
    raise SystemExit("statement title anchor missing")

p.write_text(s, encoding="utf-8")

u = p.read_text(encoding="utf-8")
checks = [
    ("voyage passed to painter", "voyage: widget.voyage," in u),
    ("voyage field exists", "final String voyage;" in u),
    ("voyage suffix normalized", "endsWith('항차')" in u),
    ("statement title includes voyage", "final statementTitle = voyageText.isEmpty" in u),
]

print("PATCH197 VERIFY")
bad = []
for name, ok in checks:
    print(("[OK] " if ok else "[FAIL] ") + name)
    if not ok:
        bad.append(name)
if bad:
    raise SystemExit("VERIFY FAILED: " + ", ".join(bad))

print("PATCH197 VERIFIED OK")
