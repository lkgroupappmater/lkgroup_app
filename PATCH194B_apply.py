from pathlib import Path
R=Path.cwd()
p=R/'lib/screens/change_approval_screen.dart'
if not p.exists(): raise SystemExit('missing change_approval_screen.dart')
s=p.read_text(encoding='utf-8-sig')

# Patch194 created `incomplete` from a fixed-length list returned by the service,
# then attempted incomplete.add(copy). Make it explicitly growable.
old="""      final incomplete =
          await UnknownRecipientService.instance.listIncompleteForAdmin();
      final manualUncertain ="""
new="""      final incomplete = <Map<String, dynamic>>[
        ...await UnknownRecipientService.instance.listIncompleteForAdmin(),
      ];
      final manualUncertain ="""
if old not in s:
    raise SystemExit('Patch194 load anchor missing')
s=s.replace(old,new,1)

p.write_text(s,encoding='utf-8')

u=p.read_text(encoding='utf-8')
ok="final incomplete = <Map<String, dynamic>>[" in u and "incomplete.add(copy);" in u
print('PATCH194B VERIFY')
print(('[OK] ' if ok else '[FAIL] ')+'growable approval list')
if not ok: raise SystemExit('VERIFY FAILED')
print('PATCH194B VERIFIED OK')
