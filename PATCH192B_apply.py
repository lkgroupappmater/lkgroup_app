from pathlib import Path
R=Path.cwd()
p=R/'lib/screens/customer_list_management_screen.dart'
if not p.exists(): raise SystemExit('customer_list_management_screen.dart missing')
s=p.read_text(encoding='utf-8-sig')

# Exact local anchors supplied by user.
old="""    const w=1600.0, headerH=82.0, colH=48.0, rowH=38.0, footerH=42.0;
    final h=headerH+colH+rowH*rows.length+footerH;"""
new="""    const w=1120.0, topH=110.0, headerH=76.0, colH=46.0, rowH=31.0, footerH=18.0;
    final pageHeaderH = page == 0 ? headerH : 0.0;
    final h=topH+pageHeaderH+colH+rowH*rows.length+footerH;"""
if old not in s: raise SystemExit('size anchor missing')
s=s.replace(old,new,1)

old="""    _paintText(c,_title,Rect.fromLTWH(0,8,w,52),30,bold:true);
    _paintText(c,'${_rows.length}명  ·  ${page+1}/$pages',Rect.fromLTWH(0,52,w,25),14);
    final y0=headerH;
    final xs=<double>[0,150,500,790,970,1120,1600];"""
new="""    if(page==0){
      _paintText(c,_title,Rect.fromLTWH(0,topH+4,w,48),28,bold:true);
      _paintText(c,'${_rows.length}명  ·  ${page+1}/$pages',Rect.fromLTWH(0,topH+48,w,22),13);
    }
    final y0=topH+pageHeaderH;
    final xs=<double>[0,120,365,575,695,785,1120];"""
if old not in s: raise SystemExit('title anchor missing')
s=s.replace(old,new,1)

s=s.replace("const perPage=36;","const perPage=32;",1)
s=s.replace("pageFormat:PdfPageFormat.a4.landscape,margin:const pw.EdgeInsets.all(10)",
            "pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.fromLTRB(10,4,10,4)",1)

p.write_text(s,encoding='utf-8')

u=p.read_text(encoding='utf-8')
checks=[
 ('portrait width','const w=1120.0' in u),
 ('top binding margin','topH=110.0' in u),
 ('first page title only','if(page==0)' in u),
 ('page 2 no title','pageHeaderH = page == 0 ? headerH : 0.0' in u),
 ('portrait PDF','pageFormat:PdfPageFormat.a4,' in u),
 ('32 rows per page','const perPage=32;' in u),
 ('small bottom','footerH=18.0' in u),
]
print('PATCH192B VERIFY'); bad=[]
for n,o in checks:
 print(('[OK] ' if o else '[FAIL] ')+n)
 if not o: bad.append(n)
if bad: raise SystemExit('VERIFY FAILED: '+', '.join(bad))
print('PATCH192B VERIFIED OK')
