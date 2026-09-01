from pathlib import Path
import re

R=Path.cwd()
p=R/'lib/screens/change_approval_screen.dart'
if not p.exists():
    raise SystemExit('missing change_approval_screen.dart')

s=p.read_text(encoding='utf-8-sig')

# Find the local Patch194 pattern flexibly, regardless of line wrapping/spacing.
pattern = re.compile(
    r"""final\s+incomplete\s*=\s*
        await\s+UnknownRecipientService\.instance\.listIncompleteForAdmin\(\)\s*;
        \s*final\s+manualUncertain\s*=""",
    re.VERBOSE | re.DOTALL,
)

replacement = """final incomplete = <Map<String, dynamic>>[
        ...await UnknownRecipientService.instance.listIncompleteForAdmin(),
      ];
      final manualUncertain ="""

s2, n = pattern.subn(replacement, s, count=1)

if n == 0:
    # If already partially hotfixed or formatted differently, inspect a smaller anchor.
    small = "await UnknownRecipientService.instance.listIncompleteForAdmin()"
    if small not in s:
        raise SystemExit('listIncompleteForAdmin call not found')
    # If growable wrapper is already present, treat as success.
    if "final incomplete = <Map<String, dynamic>>[" in s:
        print('PATCH194C: already growable - no source change needed')
        s2 = s
    else:
        # Conservative fallback: replace only the statement containing the call.
        stmt = re.compile(
            r"final\s+incomplete\s*=\s*await\s+UnknownRecipientService\.instance\.listIncompleteForAdmin\(\)\s*;",
            re.DOTALL,
        )
        s2, n2 = stmt.subn(
            """final incomplete = <Map<String, dynamic>>[
        ...await UnknownRecipientService.instance.listIncompleteForAdmin(),
      ];""",
            s,
            count=1,
        )
        if n2 == 0:
            raise SystemExit('Could not safely rewrite incomplete list')

p.write_text(s2, encoding='utf-8')

u=p.read_text(encoding='utf-8')
checks = [
    ('growable incomplete list', "final incomplete = <Map<String, dynamic>>[" in u),
    ('manual uncertain merge retained', "manualUncertain" in u),
    ('manual add retained', "incomplete.add(copy);" in u),
]
print('PATCH194C VERIFY')
bad=[]
for name, ok in checks:
    print(('[OK] ' if ok else '[FAIL] ') + name)
    if not ok: bad.append(name)
if bad:
    raise SystemExit('VERIFY FAILED: ' + ', '.join(bad))
print('PATCH194C VERIFIED OK')
