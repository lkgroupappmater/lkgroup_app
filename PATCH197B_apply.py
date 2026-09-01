from pathlib import Path

R=Path.cwd()
p=R/"lib/screens/statement_preview_dialog.dart"
if not p.exists():
    raise SystemExit("missing: lib/screens/statement_preview_dialog.dart")

s=p.read_text(encoding="utf-8-sig")

# Patch197 added required voyage to _DigitalStatementPainter.
# There is a second painter construction in the batch renderer that must also pass it.
anchor="""    final painter = _DigitalStatementPainter(
      routeLabel: request.routeLabel,
      rows: rows,
      freight: freight,
      receiptNumber: request.receiptNumber,
      arrivalDate: arrival,
"""
replacement="""    final painter = _DigitalStatementPainter(
      routeLabel: request.routeLabel,
      rows: rows,
      freight: freight,
      receiptNumber: request.receiptNumber,
      voyage: request.voyage,
      arrivalDate: arrival,
"""

if anchor in s:
    s=s.replace(anchor,replacement,1)
elif "voyage: request.voyage," not in s:
    raise SystemExit("batch painter anchor missing")

p.write_text(s,encoding="utf-8")

u=p.read_text(encoding="utf-8")
checks=[
    ("dialog painter voyage","voyage: widget.voyage," in u),
    ("batch painter voyage","voyage: request.voyage," in u),
    ("required voyage","required this.voyage," in u),
    ("voyage field","final String voyage;" in u),
]
print("PATCH197B VERIFY")
bad=[]
for name,ok in checks:
    print(("[OK] " if ok else "[FAIL] ")+name)
    if not ok: bad.append(name)
if bad:
    raise SystemExit("VERIFY FAILED: "+", ".join(bad))
print("PATCH197B VERIFIED OK")
