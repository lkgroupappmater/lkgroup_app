from pathlib import Path
R=Path.cwd()
p=R/'lib/screens/customer_list_management_screen.dart'
if not p.exists(): raise SystemExit('customer list screen missing')
s=p.read_text(encoding='utf-8-sig')

# A4 portrait: render each PDF page in portrait-friendly ratio.
s=s.replace("const w=1600.0, topH=72.0, headerH=82.0, colH=48.0, rowH=38.0, footerH=42.0;",
            "const w=1120.0, topH=105.0, headerH=76.0, colH=46.0, rowH=32.0, footerH=22.0;")
# narrower portrait columns
s=s.replace("final xs=<double>[0,150,500,790,970,1120,1600];",
            "final xs=<double>[0,120,365,575,695,785,1120];")
# first page title only; later pages begin after generous binding margin.
old="""    _paintText(c,_title,Rect.fromLTWH(0,topH+8,w,52),30,bold:true);
    _paintText(c,'${_rows.length}명  ·  ${page+1}/$pages',Rect.fromLTWH(0,topH+52,w,25),14);
    final y0=topH+headerH;"""
new="""    final firstPage = page == 0;
    final pageHeaderH = firstPage ? headerH : 0.0;
    if (firstPage) {
      _paintText(c,_title,Rect.fromLTWH(0,topH+4,w,48),28,bold:true);
      _paintText(c,'${_rows.length}명  ·  ${page+1}/$pages',Rect.fromLTWH(0,topH+48,w,22),13);
    }
    final y0=topH+pageHeaderH;"""
if old not in s: raise SystemExit('render title anchor missing')
s=s.replace(old,new,1)
# dynamic height needs firstPage knowledge; replace height setup before canvas
s=s.replace("final h=topH+headerH+colH+rowH*rows.length+footerH;",
            "final firstPageHeight = page == 0 ? headerH : 0.0;\n    final h=topH+firstPageHeight+colH+rowH*rows.length+footerH;")
# avoid duplicate final firstPage declaration after replacement
s=s.replace("    final firstPage = page == 0;\n    final pageHeaderH = firstPage ? headerH : 0.0;",
            "    final pageHeaderH = page == 0 ? headerH : 0.0;")
s=s.replace("    if (firstPage) {","    if (page == 0) {")
# fewer rows per portrait page, leaving top margin but little bottom.
s=s.replace("const perPage=30;","const perPage=32;")
# PDF portrait
s=s.replace("pageFormat:PdfPageFormat.a4.landscape","pageFormat:PdfPageFormat.a4")
# small PDF margins because image itself owns binding/top margin
s=s.replace("margin:const pw.EdgeInsets.all(10)","margin:const pw.EdgeInsets.fromLTRB(10, 4, 10, 4)")
p.write_text(s,encoding='utf-8')

# Verify cargo-management discount button already exists beside extra-cost button in current source.
cargo=R/'lib/screens/cargo_management_screen.dart'
if not cargo.exists(): raise SystemExit('cargo_management_screen.dart missing')
c=cargo.read_text(encoding='utf-8-sig')
has_extra="tooltip: '기타 비용 (+\\$)'" in c
has_discount="tooltip: rule == null ? '할인 적용' : '할인 편집 / 삭제'" in c
has_method="Future<void> _showReceiptDiscountDialog(" in c

u=p.read_text(encoding='utf-8')
checks=[
 ('A4 portrait','pageFormat:PdfPageFormat.a4,' in u),
 ('larger top binding margin','topH=105.0' in u),
 ('title first page only','if (page == 0)' in u and 'pageHeaderH = page == 0 ? headerH : 0.0' in u),
 ('column header every page',"final heads=['영수증 번호','고객명/회사명','연락처','구획(Zone)','수량','비고'];" in u),
 ('small bottom footer','footerH=22.0' in u),
 ('extra cost button exists',has_extra),
 ('discount button exists',has_discount and has_method),
]
print('PATCH192 VERIFY'); bad=[]
for n,o in checks:
 print(('[OK] ' if o else '[FAIL] ')+n)
 if not o: bad.append(n)
if bad: raise SystemExit('VERIFY FAILED: '+', '.join(bad))
print('PATCH192 VERIFIED OK')
print('NOTE: Cargo management already contains the percent button next to extra cost in current source; no duplicate button added.')
