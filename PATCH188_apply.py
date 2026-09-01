from pathlib import Path

cwd = Path.cwd()
p = cwd / "lib/screens/statement_preview_dialog.dart"

if not p.exists():
    raise SystemExit("statement_preview_dialog.dart not found")

s = p.read_text(encoding="utf-8-sig")

bad = (
    "    final finalTop = sumTop + 92;\n"
    "    final labelW = totalW * .38;\n"
    "    final labelW = totalW * .46;\n"
)

good = (
    "    final finalTop = sumTop + 92;\n"
    "    final labelW = totalW * .38;\n"
)

if bad not in s:
    # tolerate CRLF-normalized or already fixed state
    s2 = s.replace("\r\n", "\n")
    if bad in s2:
        s = s2
    elif (
        "    final finalTop = sumTop + 92;\n"
        "    final labelW = totalW * .38;\n"
    ) in s2 and "    final labelW = totalW * .46;\n" not in s2[
        s2.find("    final finalTop = sumTop + 92;"):
        s2.find("    final payTop =", s2.find("    final finalTop = sumTop + 92;"))
    ]:
        print("Patch188 already applied.")
        raise SystemExit(0)
    else:
        raise SystemExit("Exact duplicate labelW block not found; stopped without changes.")

s = s.replace(bad, good, 1)
p.write_text(s, encoding="utf-8")

u = p.read_text(encoding="utf-8")
st = u.find("    final finalTop = sumTop + 92;")
en = u.find("    final payTop =", st)
block = u[st:en]

checks = [
    ("one final-total labelW declaration",
     block.count("final labelW = totalW * .38;") == 1),
    ("bad .46 duplicate removed from final-total block",
     "final labelW = totalW * .46;" not in block),
]

print("PATCH188 VERIFY")
bad_checks = []
for name, ok in checks:
    print(("[OK] " if ok else "[FAIL] ") + name)
    if not ok:
        bad_checks.append(name)

if bad_checks:
    raise SystemExit("VERIFY FAILED: " + ", ".join(bad_checks))

print("PATCH188 VERIFIED OK")
