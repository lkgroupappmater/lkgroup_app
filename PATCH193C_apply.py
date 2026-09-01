from pathlib import Path
R=Path.cwd()
p=R/'lib/screens/customer_list_management_screen.dart'
if not p.exists(): raise SystemExit('customer_list_management_screen.dart missing')
s=p.read_text(encoding='utf-8-sig')

# Keep the page/table design exactly as-is; only stretch the print image slightly
# toward the physical bottom edge to remove the remaining bottom whitespace.
old="""          build:(_)=>pw.Image(image,fit:pw.BoxFit.fill),"""
new="""          build:(_)=>pw.Transform.scale(
            scale:1.025,
            alignment:pw.Alignment.topCenter,
            child:pw.Image(image,fit:pw.BoxFit.fill),
          ),"""
if old not in s:
    raise SystemExit('PDF image anchor missing - apply Patch193B first')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')

u=p.read_text(encoding='utf-8')
ok='scale:1.025' in u and 'alignment:pw.Alignment.topCenter' in u
print('PATCH193C VERIFY')
print(('[OK] ' if ok else '[FAIL] ')+'reduce bottom whitespace only')
if not ok: raise SystemExit('VERIFY FAILED')
print('PATCH193C VERIFIED OK')
