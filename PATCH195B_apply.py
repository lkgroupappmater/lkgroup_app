from pathlib import Path
import re

R = Path.cwd()
p = R / "lib/screens/quotation_preview_dialog.dart"
if not p.exists():
    raise SystemExit("missing: lib/screens/quotation_preview_dialog.dart")

s = p.read_text(encoding="utf-8-sig")

# Patch195 compile hotfix:
# safeDiscountPercent was declared after its first use inside paint().
# Move it to the very beginning of paint(), and remove the later duplicate declaration.

paint_anchor = """  @override
  void paint(Canvas c, Size size) {
    final w = size.width;"""

paint_new = """  @override
  void paint(Canvas c, Size size) {
    final safeDiscountPercent =
        discountPercent.clamp(0, 100).toDouble();
    final w = size.width;"""

if paint_anchor in s:
    s = s.replace(paint_anchor, paint_new, 1)
elif "final safeDiscountPercent =" not in s[:s.find("final w = size.width;")+200]:
    raise SystemExit("paint() anchor missing")

# Remove the later declaration introduced by Patch195.
later = """    final safeDiscountPercent = discountPercent.clamp(0, 100).toDouble();
"""
count = s.count(later)
if count > 0:
    # Keep the first declaration near paint() and remove any later copies.
    first = s.find(later)
    paint_pos = s.find("void paint(Canvas c, Size size)")
    if first > paint_pos and first < s.find("final w = size.width;") + 200:
        # first is the correct early declaration; remove subsequent copies only
        pos = s.find(later, first + len(later))
        while pos != -1:
            s = s[:pos] + s[pos+len(later):]
            pos = s.find(later, pos)
    else:
        # if exact one-line declaration remains only later, remove it
        s = s.replace(later, "", 1)

# Handle formatted/multiline late declaration if formatter changed it.
pattern = re.compile(
    r"""(?ms)^\s{4}final safeDiscountPercent\s*=\s*
        discountPercent\.clamp\(0,\s*100\)\.toDouble\(\);\s*$"""
)
matches = list(pattern.finditer(s))
if len(matches) > 1:
    # Preserve the earliest one only.
    for m in reversed(matches[1:]):
        s = s[:m.start()] + s[m.end():]

p.write_text(s, encoding="utf-8")

u = p.read_text(encoding="utf-8")
paint = u.find("void paint(Canvas c, Size size)")
decl = u.find("final safeDiscountPercent", paint)
first_use = u.find("safeDiscountPercent", decl + 1)
wpos = u.find("final w = size.width;", paint)

checks = [
    ("declaration exists", decl != -1),
    ("declaration before normal paint body", decl < wpos),
    ("first use occurs after declaration", first_use > decl),
    ("only one declaration", u.count("final safeDiscountPercent") == 1),
]

print("PATCH195B VERIFY")
bad = []
for name, ok in checks:
    print(("[OK] " if ok else "[FAIL] ") + name)
    if not ok:
        bad.append(name)

if bad:
    raise SystemExit("VERIFY FAILED: " + ", ".join(bad))

print("PATCH195B VERIFIED OK")
