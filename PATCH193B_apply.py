from pathlib import Path
import re

R = Path.cwd()
p = R / 'lib/screens/customer_list_management_screen.dart'
if not p.exists():
    raise SystemExit('customer_list_management_screen.dart missing')

s = p.read_text(encoding='utf-8-sig')

old = '''        result.add({
          'receipt':e.key,'name':'${first['consignee_name']??''}'.trim(),
          'phone':'${first['consignee_phone']??''}'.trim(),'zone':'${first['unloading_zone']??''}'.trim(),
          'note':notes,'rows':e.value.length,'quantity':qty,
        });
      }
      if(!mounted)return;
      setState((){_rows=result;_loading=false;});'''

new = '''        final boxes=e.value
            .map((r)=>'${r['box_number']??''}'.trim())
            .where((v)=>v.isNotEmpty)
            .toSet()
            .toList(growable:false);
        final delivery=_deliveryOnlyLabel(notes);
        result.add({
          'receipt':e.key,'name':'${first['consignee_name']??''}'.trim(),
          'phone':'${first['consignee_phone']??''}'.trim(),'zone':'${first['unloading_zone']??''}'.trim(),
          'note':notes,'delivery':delivery,'boxes':boxes,'rows':e.value.length,'quantity':qty,
        });
      }
      int receiptNo(String v){
        final m=RegExp(r'(\\d+)').firstMatch(v);
        return m==null ? 999999 : (int.tryParse(m.group(1)!) ?? 999999);
      }
      bool isUnknownReceipt(Map<String,dynamic> row){
        final receipt='${row['receipt']??''}'.trim().toUpperCase();
        final name='${row['name']??''}'.trim();
        final hasNumber=RegExp(r'\\d+').hasMatch(receipt);
        return !hasNumber ||
            receipt.contains('XX') ||
            name.contains('수취인 불명') ||
            name.contains('수취인불명') ||
            name.contains('미확인');
      }
      bool isPark100(Map<String,dynamic> row){
        final receipt='${row['receipt']??''}'.trim();
        final name='${row['name']??''}'.replaceAll(RegExp(r'\\s+'),'');
        return receiptNo(receipt)==100 || name.startsWith('박성호');
      }
      result.sort((a,b){
        final au=isUnknownReceipt(a), bu=isUnknownReceipt(b);
        if(au!=bu)return au?1:-1; // unknown is absolute last
        final ap=isPark100(a), bp=isPark100(b);
        if(ap!=bp)return ap?1:-1; // Park/LKS100 sits immediately before unknown
        final aa=receiptNo('${a['receipt']??''}');
        final bb=receiptNo('${b['receipt']??''}');
        if(aa!=bb)return aa.compareTo(bb);
        return '${a['receipt']??''}'.compareTo('${b['receipt']??''}');
      });
      if(!mounted)return;
      setState((){_rows=result;_loading=false;});'''

if old not in s:
    raise SystemExit('grouping anchor missing')
s = s.replace(old, new, 1)

anchor = '''  Widget _selector<T>({required String label,required T? value,required List<T> items,'''
helper = '''  String _deliveryOnlyLabel(String text) {
    final t=text.replaceAll(RegExp(r'\\s+'),' ');
    if(t.contains('지방배송(선결제)')) return '지방배송(선결제)';
    if(t.contains('시내배송(선결제)')) return '시내배송(선결제)';
    if(t.contains('지방배송')) return '지방배송';
    if(t.contains('시내배송')) return '시내배송';
    return '';
  }

  Color? _deliveryFill(String label) {
    switch(label) {
      case '지방배송': return const Color(0xFFFFC000);
      case '지방배송(선결제)': return const Color(0xFF5B9BD5);
      case '시내배송': return const Color(0xFF92D050);
      case '시내배송(선결제)': return const Color(0xFFFFFF00);
      default: return null;
    }
  }

  List<String> _boxLines(Map<String,dynamic> row) {
    final boxes=((row['boxes'] as List?) ?? const [])
        .map((e)=>'$e'.trim()).where((e)=>e.isNotEmpty).toList(growable:false);
    if(boxes.isEmpty) return const [''];
    final out=<String>[];
    for(var i=0;i<boxes.length;i+=10){
      out.add(boxes.skip(i).take(10).join(', '));
    }
    return out;
  }

  int _rowUnits(Map<String,dynamic> row) => _boxLines(row).length.clamp(1, 999);

  List<List<Map<String,dynamic>>> _printPages() {
    const unitsPerPage=25;
    final pages=<List<Map<String,dynamic>>>[];
    var current=<Map<String,dynamic>>[];
    var used=0;
    for(final row in _rows){
      final units=_rowUnits(row);
      if(current.isNotEmpty && used+units>unitsPerPage){
        pages.add(current);
        current=<Map<String,dynamic>>[];
        used=0;
      }
      current.add(row);
      used+=units;
    }
    if(current.isNotEmpty) pages.add(current);
    return pages;
  }

'''
if anchor not in s:
    raise SystemExit('selector anchor missing')
s = s.replace(anchor, helper + anchor, 1)

start = s.find('  Future<Uint8List> _renderPage(')
end = s.find('  Future<void> _saveImage()', start)
if start < 0 or end < 0:
    raise SystemExit('render function range missing')

render = '''  Future<Uint8List> _renderPage(List<Map<String,dynamic>> rows,{required int page,required int pages}) async {
    const w=1120.0, h=1584.0;
    const topMargin=50.0;
    const titleH=54.0;
    const colH=44.0;
    const unitH=56.0;

    final rec=ui.PictureRecorder();
    final c=Canvas(rec);
    c.drawRect(Rect.fromLTWH(0,0,w,h),Paint()..color=Colors.white);

    final line=Paint()
      ..color=const Color(0xFF7890A4)
      ..style=PaintingStyle.stroke
      ..strokeWidth=1;
    final headerFill=Paint()..color=const Color(0xFFE7F0F7);

    var y=topMargin;
    if(page==0){
      _paintText(c,_title,Rect.fromLTWH(26,y,w-52,36),22,bold:true);
      _paintText(c,'${_rows.length}명  ·  ${page+1}/$pages',Rect.fromLTWH(26,y+34,w-52,18),11);
      y+=titleH;
    }

    const left=26.0;
    const right=1094.0;
    final xs=<double>[left,145,390,505,760,840,right];
    final heads=['영수증 번호','고객명/회사명','구획(Zone)','박스 번호','수량','서명(Sign)'];

    for(var i=0;i<heads.length;i++){
      final r=Rect.fromLTRB(xs[i],y,xs[i+1],y+colH);
      c.drawRect(r,headerFill);
      c.drawRect(r,line);
      _paintText(c,heads[i],r,14,bold:true);
    }
    y+=colH;

    for(final row in rows){
      final boxLines=_boxLines(row);
      final rowH=unitH*boxLines.length;
      final delivery='${row['delivery']??''}';
      final values=<String>[
        '${row['receipt']??''}',
        '${row['name']??''}',
        '${row['zone']??''}',
        '',
        '${row['quantity']??''}',
        delivery,
      ];

      for(var i=0;i<values.length;i++){
        final r=Rect.fromLTRB(xs[i],y,xs[i+1],y+rowH);
        if(i==5){
          final fill=_deliveryFill(delivery);
          if(fill!=null)c.drawRect(r,Paint()..color=fill);
        }
        c.drawRect(r,line);

        if(i==3){
          for(var b=0;b<boxLines.length;b++){
            final br=Rect.fromLTRB(xs[i],y+unitH*b,xs[i+1],y+unitH*(b+1));
            _paintText(c,boxLines[b],br,11,bold:false,align:TextAlign.center);
          }
        }else{
          final size=i==1 ? 15.0 : (i==5 ? 12.0 : 14.0);
          _paintText(c,values[i],r,size,bold:i==0||i==1||i==2,align:TextAlign.center);
        }
      }
      y+=rowH;
    }

    final pic=rec.endRecording();
    final img=await pic.toImage(w.toInt(),h.toInt());
    final bd=await img.toByteData(format:ui.ImageByteFormat.png);
    if(bd==null)throw StateError('PNG 생성 실패');
    return bd.buffer.asUint8List();
  }

'''
s = s[:start] + render + s[end:]

# known current PDF block
old_pdf_1 = '''      const perPage=32;
      final pages=(_rows.length/perPage).ceil();
      final doc=pw.Document();
      for(var p=0;p<pages;p++){
        final slice=_rows.skip(p*perPage).take(perPage).toList(growable:false);
        final png=await _renderPage(slice,page:p,pages:pages);
        final image=pw.MemoryImage(png);
        doc.addPage(pw.Page(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.fromLTRB(10,4,10,4),
          build:(_)=>pw.Center(child:pw.Image(image,fit:pw.BoxFit.contain))));
      }'''
old_pdf_2 = '''      const perPage=36;
      final pages=(_rows.length/perPage).ceil();
      final doc=pw.Document();
      for(var p=0;p<pages;p++){
        final slice=_rows.skip(p*perPage).take(perPage).toList(growable:false);
        final png=await _renderPage(slice,page:p,pages:pages);
        final image=pw.MemoryImage(png);
        doc.addPage(pw.Page(pageFormat:PdfPageFormat.a4.landscape,margin:const pw.EdgeInsets.all(10),
          build:(_)=>pw.Center(child:pw.Image(image,fit:pw.BoxFit.contain))));
      }'''
new_pdf = '''      final pageRows=_printPages();
      final pages=pageRows.length;
      final doc=pw.Document();
      for(var p=0;p<pages;p++){
        final png=await _renderPage(pageRows[p],page:p,pages:pages);
        final image=pw.MemoryImage(png);
        doc.addPage(pw.Page(
          pageFormat:PdfPageFormat.a4,
          margin:pw.EdgeInsets.zero,
          build:(_)=>pw.Image(image,fit:pw.BoxFit.fill),
        ));
      }'''
if old_pdf_1 in s:
    s=s.replace(old_pdf_1,new_pdf,1)
elif old_pdf_2 in s:
    s=s.replace(old_pdf_2,new_pdf,1)
else:
    raise SystemExit('PDF pagination anchor missing')

old_img = '      final bytes=await _renderPage(_rows,page:0,pages:1);'
new_img = '''      final pageRows=_printPages();
      if(pageRows.isEmpty)return;
      final bytes=await _renderPage(pageRows.first,page:0,pages:pageRows.length);'''
if old_img not in s:
    raise SystemExit('image save anchor missing')
s=s.replace(old_img,new_img,1)

p.write_text(s,encoding='utf-8')

u=p.read_text(encoding='utf-8')
checks=[
    ('receipt order + Park100 + unknown last',"isUnknownReceipt" in u and "isPark100" in u and "result.sort((a,b)" in u),
    ('requested columns',"['영수증 번호','고객명/회사명','구획(Zone)','박스 번호','수량','서명(Sign)']" in u),
    ('25 row units',"const unitsPerPage=25;" in u),
    ('10 boxes per line',"i+=10" in u and "take(10)" in u),
    ('delivery in signature',"if(i==5)" in u and "_deliveryFill(delivery)" in u),
    ('delivery colors',"0xFFFFC000" in u and "0xFF5B9BD5" in u and "0xFF92D050" in u and "0xFFFFFF00" in u),
    ('A4 portrait',"const w=1120.0, h=1584.0;" in u and "pageFormat:PdfPageFormat.a4" in u),
    ('top margin',"const topMargin=50.0;" in u),
]
print('PATCH193B VERIFY')
bad=[]
for name, ok in checks:
    print(('[OK] ' if ok else '[FAIL] ')+name)
    if not ok: bad.append(name)
if bad:
    raise SystemExit('VERIFY FAILED: '+', '.join(bad))
print('PATCH193B VERIFIED OK')
