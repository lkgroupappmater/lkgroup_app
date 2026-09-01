from pathlib import Path
R=Path.cwd()
p=R/'lib/screens/customer_list_management_screen.dart'
if not p.exists(): raise SystemExit('customer_list_management_screen.dart missing')
s=p.read_text(encoding='utf-8-sig')

# 1) Restore Lao title text beside the Korean title.
old = """    return '$route ${_year ?? ''} ${_voyage ?? ''}항차 고객 리스트';"""
new = """    return '$route ${_year ?? ''} ${_voyage ?? ''}항차 고객 리스트 (ລາຍການລູກຄ້າຂອງທາງເຮືອ)';"""
if old in s:
    s=s.replace(old,new,1)

# 2) Keep page 1 placement, but page 2+ should retain only about the same
#    top blank space that exists above the title on page 1.
# Current renderer uses var y=topMargin for all pages, which already does this.
# Make the intent explicit and a touch more compact.
s=s.replace("const topMargin=50.0;","const topMargin=48.0;",1)

# 3) Increase print readability.
# Header labels: slightly larger overall.
s=s.replace("_paintText(c,heads[i],r,14,bold:true);",
            "_paintText(c,heads[i],r,18,bold:true);",1)

# Box numbers: about double.
s=s.replace("_paintText(c,boxLines[b],br,11,bold:false,align:TextAlign.center);",
            "_paintText(c,boxLines[b],br,22,bold:false,align:TextAlign.center);",1)

# Main row text: receipt/name/zone/quantity roughly double.
old_sizes = """          final size=i==1 ? 15.0 : (i==5 ? 12.0 : 14.0);
          _paintText(c,values[i],r,size,bold:i==0||i==1||i==2,align:TextAlign.center);"""
new_sizes = """          final size=i==1
              ? 30.0
              : (i==5 ? 24.0 : 28.0);
          _paintText(
            c,
            values[i],
            r,
            size,
            bold:i==0||i==1||i==2||i==4||i==5,
            align:TextAlign.center,
          );"""
if old_sizes not in s:
    raise SystemExit('font-size anchor missing - apply Patch193B/C first')
s=s.replace(old_sizes,new_sizes,1)

p.write_text(s,encoding='utf-8')

u=p.read_text(encoding='utf-8')
checks=[
 ('Lao title restored','ລາຍການລູກຄ້າ' in u),
 ('top margin compact','const topMargin=48.0;' in u),
 ('header font larger','_paintText(c,heads[i],r,18,bold:true);' in u),
 ('box font doubled','boxLines[b],br,22' in u),
 ('name font doubled','? 30.0' in u),
 ('receipt-zone-qty font doubled',': (i==5 ? 24.0 : 28.0)' in u),
 ('signature font larger','i==5 ? 24.0' in u),
]
print('PATCH193D VERIFY')
bad=[]
for n,o in checks:
    print(('[OK] ' if o else '[FAIL] ')+n)
    if not o: bad.append(n)
if bad: raise SystemExit('VERIFY FAILED: '+', '.join(bad))
print('PATCH193D VERIFIED OK')
