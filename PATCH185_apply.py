from pathlib import Path
import re

cwd = Path.cwd()

def rd(p):
    return p.read_text(encoding="utf-8-sig")

def wr(p, s):
    p.write_text(s, encoding="utf-8")

def matching_paren(text, open_pos):
    depth = 0
    quote = None
    escape = False
    for i in range(open_pos, len(text)):
        ch = text[i]
        if quote:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1

# Find the ACTUAL local file containing both the visible title and destination.
candidates = []
for f in (cwd / "lib").rglob("*.dart"):
    if f.name == "customer_list_management_screen.dart":
        continue
    t = rd(f)
    if "하역 자료 관리" in t and "UnloadingListManagementScreen" in t:
        candidates.append((f, t))

if not candidates:
    raise SystemExit(
        "No local menu file contains both '하역 자료 관리' and "
        "'UnloadingListManagementScreen'."
    )

menu, s = candidates[0]
dest = s.find("UnloadingListManagementScreen")
title = s.rfind("하역 자료 관리", 0, dest + 1)
if title < 0:
    title = s.find("하역 자료 관리", dest)
if title < 0:
    raise SystemExit("Visible unloading menu title not found near destination.")

# Search all enclosing function-call parentheses from the destination outward.
# Pick the smallest call block that contains BOTH the title and destination.
blocks = []
for m in re.finditer(r"([A-Za-z_][A-Za-z0-9_\.]*)\s*\(", s[:dest + 1]):
    open_pos = s.find("(", m.start(), m.end())
    close_pos = matching_paren(s, open_pos)
    if close_pos < 0 or not (open_pos < dest < close_pos):
        continue
    start = m.start()
    block = s[start:close_pos + 1]
    if "하역 자료 관리" in block and "UnloadingListManagementScreen" in block:
        blocks.append((close_pos - start, start, close_pos + 1, block))

if not blocks:
    excerpt_start = max(0, title - 900)
    excerpt_end = min(len(s), dest + 900)
    print("----- MENU EXCERPT START -----")
    print(s[excerpt_start:excerpt_end])
    print("----- MENU EXCERPT END -----")
    raise SystemExit("Could not identify enclosing unloading menu call.")

blocks.sort(key=lambda x: x[0])
_, start, end, block = blocks[0]

# Include trailing comma/semicolon if present.
j = end
while j < len(s) and s[j] in " \t":
    j += 1
if j < len(s) and s[j] in ",;":
    end = j + 1
    block = s[start:end]

# Ensure import.
if "customer_list_management_screen.dart" not in s:
    imports = list(re.finditer(r"^import\s+['\"].*?['\"];\s*$", s, re.M))
    if not imports:
        raise SystemExit("No import anchor in management menu file.")
    pos = imports[-1].end()
    target = cwd / "lib/screens/customer_list_management_screen.dart"
    rel = target.relative_to(menu.parent)
    imp = str(rel).replace("\\", "/")
    if not imp.startswith("."):
        imp = "./" + imp
    s = s[:pos] + f"\nimport '{imp}';" + s[pos:]
    # imports change offsets; refind block in updated source.
    dest = s.find("UnloadingListManagementScreen")
    blocks = []
    for m in re.finditer(r"([A-Za-z_][A-Za-z0-9_\.]*)\s*\(", s[:dest + 1]):
        op = s.find("(", m.start(), m.end())
        cp = matching_paren(s, op)
        if cp < 0 or not (op < dest < cp):
            continue
        b = s[m.start():cp + 1]
        if "하역 자료 관리" in b and "UnloadingListManagementScreen" in b:
            blocks.append((cp - m.start(), m.start(), cp + 1, b))
    if not blocks:
        raise SystemExit("Menu block lost after import insertion.")
    blocks.sort(key=lambda x: x[0])
    _, start, end, block = blocks[0]
    j = end
    while j < len(s) and s[j] in " \t":
        j += 1
    if j < len(s) and s[j] in ",;":
        end = j + 1
        block = s[start:end]

if "CustomerListManagementScreen" not in s:
    customer = block
    customer = customer.replace(
        "UnloadingListManagementScreen",
        "CustomerListManagementScreen",
    )
    customer = customer.replace("하역 자료 관리", "고객 리스트")
    customer = customer.replace("하역 자료", "고객 리스트")
    # Icon is cosmetic; replace common unloading icons if present.
    for old_icon in (
        "Icons.inventory_2_outlined",
        "Icons.view_module_outlined",
        "Icons.grid_view_outlined",
        "Icons.local_shipping_outlined",
    ):
        customer = customer.replace(old_icon, "Icons.people_alt_outlined")
    s = s[:end] + "\n" + customer + s[end:]

wr(menu, s)

# Verification of ALL Patch184 target changes, because Patch184 stopped late and
# may have partially applied.
checks = {
    "customer screen file": (cwd / "lib/screens/customer_list_management_screen.dart").exists(),
    "management menu link": (
        "CustomerListManagementScreen" in rd(menu)
        and "고객 리스트" in rd(menu)
    ),
    "statement 2/3 percent layout": (
        "final percentX = totalX + totalW * .54;" in
        rd(cwd / "lib/screens/statement_preview_dialog.dart")
    ),
    "CEO strong identity match": (
        "Some confirmed BASE identities use a non-numeric token" in
        rd(cwd / "lib/services/freight_service.dart")
    ),
    "Excel ordinary formula preserved": (
        "Keep the original A/B/C/F Excel formula for ordinary customers." in
        rd(cwd / "supabase/functions/export-shipment-excel/index.ts")
    ),
}

print("PATCH185 VERIFY")
print("Management menu file:", menu)
bad = []
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
    if not ok:
        bad.append(name)

if bad:
    raise SystemExit("VERIFY FAILED: " + ", ".join(bad))

print("PATCH185 VERIFIED OK")
