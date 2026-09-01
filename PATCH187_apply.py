from pathlib import Path
import re

cwd = Path.cwd()
p = cwd / "lib/screens/statement_preview_dialog.dart"
if not p.exists():
    raise SystemExit("statement_preview_dialog.dart not found")

s = p.read_text(encoding="utf-8-sig")

# -------- 1) Repair ONLY the adjustment section --------
adj_start = s.find("    // Three clear columns: label | percent (~2/3) | amount (far right).")
final_top = s.find("    final finalTop =", adj_start)

if adj_start < 0 or final_top < 0:
    raise SystemExit("Adjustment/final-total anchors not found")

adj = s[adj_start:final_top]

# Remove any duplicate width declaration created by prior hotfixes.
adj = re.sub(
    r"(?m)^    final (?:labelW|adjustmentLabelW|adjustmentColumnLabelW) = totalW \* \.46;\r?\n",
    "",
    adj,
)

# Insert one unique declaration immediately after adjustmentFont.
font_line = "    const adjustmentFont = 15.0;\n"
if font_line not in adj:
    raise SystemExit("adjustmentFont anchor not found")

adj = adj.replace(
    font_line,
    font_line + "    final adjustmentColumnLabelW = totalW * .46;\n",
    1,
)

# All label widths inside ONLY this adjustment section use the unique name.
adj = re.sub(
    r"Rect\.fromLTWH\(totalX \+ 12, (sumTop \+ (?:7|34|61)), (?:labelW|adjustmentLabelW|adjustmentColumnLabelW), adjH\)",
    r"Rect.fromLTWH(totalX + 12, \1, adjustmentColumnLabelW, adjH)",
    adj,
)

s = s[:adj_start] + adj + s[final_top:]

# -------- 2) Repair ONLY the final-total section --------
final_top = s.find("    final finalTop =", adj_start)
pay_top = s.find("    final payTop =", final_top)
if final_top < 0 or pay_top < 0:
    raise SystemExit("Final-total/pay anchors not found")

total_block = s[final_top:pay_top]

# Prior Patch186 may have accidentally renamed this original final-total labelW.
# Normalize exactly one declaration here back to labelW = .38.
total_block = re.sub(
    r"(?m)^    final (?:labelW|adjustmentLabelW|adjustmentColumnLabelW) = totalW \* \.38;\r?\n",
    "",
    total_block,
)
total_block = total_block.replace(
    "    final finalTop = sumTop + 92;\n",
    "    final finalTop = sumTop + 92;\n"
    "    final labelW = totalW * .38;\n",
    1,
)

# This section is supposed to use the original labelW throughout.
total_block = total_block.replace("adjustmentLabelW", "labelW")
total_block = total_block.replace("adjustmentColumnLabelW", "labelW")

s = s[:final_top] + total_block + s[pay_top:]

p.write_text(s, encoding="utf-8")

# -------- 3) Hard verification --------
u = p.read_text(encoding="utf-8")
a0 = u.find("    // Three clear columns: label | percent (~2/3) | amount (far right).")
f0 = u.find("    final finalTop =", a0)
p0 = u.find("    final payTop =", f0)
adj2 = u[a0:f0]
total2 = u[f0:p0]

checks = [
    ("one unique adjustment width declaration",
     adj2.count("final adjustmentColumnLabelW = totalW * .46;") == 1),
    ("no labelW declaration in adjustment section",
     "final labelW = totalW * .46;" not in adj2 and
     "final adjustmentLabelW = totalW * .46;" not in adj2),
    ("three adjustment label references repaired",
     adj2.count("adjustmentColumnLabelW, adjH)") == 3),
    ("final total original labelW restored",
     total2.count("final labelW = totalW * .38;") == 1),
    ("no adjustment width name in final total section",
     "adjustmentLabelW" not in total2 and
     "adjustmentColumnLabelW" not in total2),
]

print("PATCH187 VERIFY")
bad = []
for name, ok in checks:
    print(("[OK] " if ok else "[FAIL] ") + name)
    if not ok:
        bad.append(name)

if bad:
    raise SystemExit("VERIFY FAILED: " + ", ".join(bad))

print("PATCH187 VERIFIED OK")
