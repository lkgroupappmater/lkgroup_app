from pathlib import Path

cwd = Path.cwd()
p = cwd / "lib/screens/statement_preview_dialog.dart"

if not p.exists():
    raise SystemExit("statement_preview_dialog.dart not found")

s = p.read_text(encoding="utf-8-sig")

old_decl = "final labelW = totalW * .46;"
new_decl = "final adjustmentLabelW = totalW * .46;"

# We only patch the adjustment block introduced by Patch184/185.
anchor = "final percentX = totalX + totalW * .54;"
anchor_pos = s.find(anchor)
if anchor_pos < 0:
    raise SystemExit("Patch184 adjustment layout anchor not found")

# Find the closest labelW declaration immediately before the percent layout anchor.
decl_pos = s.rfind(old_decl, 0, anchor_pos)
if decl_pos < 0:
    # Maybe declaration was already renamed; verify usage and exit safely.
    if "final adjustmentLabelW = totalW * .46;" in s:
        print("Patch186 already applied.")
        raise SystemExit(0)
    raise SystemExit("Adjustment labelW declaration not found")

# Limit replacements to the adjustment block only.
block_start = s.rfind("final isSpecialDiscount", 0, decl_pos)
block_end = s.find("final finalTop =", anchor_pos)
if block_start < 0 or block_end < 0:
    raise SystemExit("Adjustment block boundaries not found")

block = s[block_start:block_end]
block = block.replace(old_decl, new_decl, 1)

# Replace only the width variable references inside this adjustment block.
# Avoid touching unrelated labelW declarations elsewhere in the file.
block = block.replace("labelW, adjH)", "adjustmentLabelW, adjH)")

s = s[:block_start] + block + s[block_end:]

p.write_text(s, encoding="utf-8")

# Verify:
updated = p.read_text(encoding="utf-8")
segment = updated[block_start:block_start + len(block) + 200]
checks = [
    ("renamed declaration", "final adjustmentLabelW = totalW * .46;" in segment),
    ("no old adjustment declaration", "final labelW = totalW * .46;" not in segment),
    ("adjustment uses new name", segment.count("adjustmentLabelW, adjH)") >= 3),
]
bad = [name for name, ok in checks if not ok]

print("PATCH186 VERIFY")
for name, ok in checks:
    print(("[OK] " if ok else "[FAIL] ") + name)

if bad:
    raise SystemExit("VERIFY FAILED: " + ", ".join(bad))

print("PATCH186 VERIFIED OK")
