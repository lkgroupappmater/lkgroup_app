import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/supabase_service.dart';

class CustomerListManagementScreen extends StatefulWidget {
  const CustomerListManagementScreen({super.key});
  @override
  State<CustomerListManagementScreen> createState() => _CustomerListManagementScreenState();
}

class _CustomerListManagementScreenState extends State<CustomerListManagementScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _route;
  int? _year;
  String? _voyage;
  List<Map<String, dynamic>> _batches = const [];
  List<Map<String, dynamic>> _rows = const [];

  List<String> get _routes => {for (final r in _batches) '${r['route'] ?? ''}'.trim()}
      .where((e) => e.isNotEmpty).toList()..sort();
  List<int> get _years => {for (final r in _batches) if ((r['shipment_year'] as num?)?.toInt() case final int y) y}
      .toList()..sort((a,b)=>b.compareTo(a));
  List<String> get _voyages => {for (final r in _batches)
    if (_route == '${r['route'] ?? ''}'.trim() && _year == (r['shipment_year'] as num?)?.toInt())
      '${r['voyage'] ?? ''}'.trim()}
      .where((e)=>e.isNotEmpty).toList()
    ..sort((a,b) {
      int n(String v)=>int.tryParse(v.replaceAll(RegExp(r'[^0-9]'),''))??0;
      return n(b).compareTo(n(a));
    });

  @override
  void initState(){super.initState();_loadBatches();}

  Future<void> _loadBatches() async {
    try {
      final raw=await SupabaseService.client.from('shipments')
          .select('route,shipment_year,voyage').isFilter('deletion_requested_at',null)
          .order('shipment_year',ascending:false);
      final all=(raw as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList(growable:false);
      if(!mounted)return;
      setState(() {
        _batches=all; _route=_routes.isNotEmpty?_routes.first:null;
        _year=_years.isNotEmpty?_years.first:null; _voyage=_voyages.isNotEmpty?_voyages.first:null;
        _loading=false;
      });
      await _loadRows();
    } catch(e){_fail('고객 리스트 조회 실패: $e');}
  }

  num _num(dynamic v)=>v is num?v:(num.tryParse('${v??''}')??0);

  Future<void> _loadRows() async {
    if(_route==null||_year==null||_voyage==null)return;
    setState(()=>_loading=true);
    try {
      final raw=await SupabaseService.client.from('shipments').select(
        'id,receipt_number,consignee_name,consignee_phone,unloading_zone,special_note_auto,box_number,quantity'
      ).eq('route',_route!).eq('shipment_year',_year!).eq('voyage',_voyage!)
       .isFilter('deletion_requested_at',null).order('receipt_number').order('box_number');
      final source=(raw as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList(growable:false);
      final grouped=<String,List<Map<String,dynamic>>>{};
      for(final row in source){
        final receipt='${row['receipt_number']??''}'.trim();
        if(receipt.isEmpty)continue;
        grouped.putIfAbsent(receipt,()=>[]).add(row);
      }
      final result=<Map<String,dynamic>>[];
      for(final e in grouped.entries){
        final first=e.value.first;
        final qty=e.value.fold<num>(0,(a,r)=>a+_num(r['quantity']));
        final notes=e.value.map((r)=>'${r['special_note_auto']??''}'.trim()).where((v)=>v.isNotEmpty).toSet().join(' / ');
        final boxes=e.value
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
        final m=RegExp(r'(\d+)').firstMatch(v);
        return m==null ? 999999 : (int.tryParse(m.group(1)!) ?? 999999);
      }
      bool isUnknownReceipt(Map<String,dynamic> row){
        final receipt='${row['receipt']??''}'.trim().toUpperCase();
        final name='${row['name']??''}'.trim();
        final hasNumber=RegExp(r'\d+').hasMatch(receipt);
        return !hasNumber ||
            receipt.contains('XX') ||
            name.contains('수취인 불명') ||
            name.contains('수취인불명') ||
            name.contains('미확인');
      }
      bool isPark100(Map<String,dynamic> row){
        final receipt='${row['receipt']??''}'.trim();
        final name='${row['name']??''}'.replaceAll(RegExp(r'\s+'),'');
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
      setState((){_rows=result;_loading=false;});
    }catch(e){_fail('고객 리스트 조회 실패: $e');}
  }

  void _fail(String m){
    if(!mounted)return; setState(()=>_loading=false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(m)));
  }

  Future<void> _edit(Map<String,dynamic> r) async {
    final receipt=TextEditingController(text:'${r['receipt']}');
    final zone=TextEditingController(text:'${r['zone']}');
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('${r['name']} 수정'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:receipt,decoration:const InputDecoration(labelText:'영수증 번호')),
        const SizedBox(height:10),
        TextField(controller:zone,decoration:const InputDecoration(labelText:'구획(Zone)')),
        const SizedBox(height:8),
        const Text('현재 영수증 번호에 묶인 화물 전체에 동일하게 적용됩니다.',style:TextStyle(fontSize:12)),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('취소')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('저장')),
      ],
    ));
    if(ok!=true)return;
    final nr=receipt.text.trim(), nz=zone.text.trim().toUpperCase();
    if(nr.isEmpty||nz.isEmpty)return;
    try{
      await SupabaseService.client.from('shipments').update({
        'receipt_number':nr,'unloading_zone':nz,
      }).eq('route',_route!).eq('shipment_year',_year!).eq('voyage',_voyage!)
       .eq('receipt_number','${r['receipt']}').isFilter('deletion_requested_at',null);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('영수증 번호 / Zone 수정 완료')));
      await _loadRows();
    }catch(e){_fail('수정 실패: $e');}
  }

  String _deliveryOnlyLabel(String text) {
    final t=text.replaceAll(RegExp(r'\s+'),' ');
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

  Widget _selector<T>({required String label,required T? value,required List<T> items,
    required String Function(T) text,required ValueChanged<T?> onChanged}) {
    return DropdownButtonFormField<T>(
      value:items.contains(value)?value:null,isExpanded:true,
      decoration:InputDecoration(labelText:label,border:const OutlineInputBorder(),
        isDense:true,contentPadding:const EdgeInsets.symmetric(horizontal:8,vertical:10)),
      items:items.map((e)=>DropdownMenuItem(value:e,child:Text(text(e),overflow:TextOverflow.ellipsis))).toList(),
      onChanged:onChanged,
    );
  }

  String get _title {
    final route = (_route ?? '').replaceAll('_', '-').toUpperCase();
    return '$route ${_year ?? ''} ${_voyage ?? ''}항차 고객 리스트 (ລາຍການລູກຄ້າຂອງທາງເຮືອ)';
  }

  void _paintText(Canvas c,String text,Rect r,double size,{bool bold=false,TextAlign align=TextAlign.center}) {
    final tp=TextPainter(
      text:TextSpan(text:text,style:TextStyle(fontFamily:'NotoSansKR',fontSize:size,
        fontWeight:bold?FontWeight.w700:FontWeight.w400,color:Colors.black)),
      textDirection:TextDirection.ltr,textAlign:align,maxLines:1,ellipsis:'…',
    )..layout(maxWidth:r.width-8);
    double x=r.left+4;
    if(align==TextAlign.center)x=r.left+(r.width-tp.width)/2;
    if(align==TextAlign.right)x=r.right-tp.width-4;
    tp.paint(c,Offset(x,r.top+(r.height-tp.height)/2));
  }

  Future<Uint8List> _renderPage(List<Map<String,dynamic>> rows,{required int page,required int pages}) async {
    const w=1120.0, h=1584.0;
    const topMargin=48.0;
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
    final xs=<double>[left,145,370,480,790,860,right];
    final heads=['영수증 번호','고객명/회사명','구획(Zone)','박스 번호','수량','서명(Sign)'];

    for(var i=0;i<heads.length;i++){
      final r=Rect.fromLTRB(xs[i],y,xs[i+1],y+colH);
      c.drawRect(r,headerFill);
      c.drawRect(r,line);
      _paintText(c,heads[i],r,15,bold:true);
    }
    y+=colH;

    for(final row in rows){
      final receiptText='${row['receipt']??''}'.trim();
      final nameText='${row['name']??''}'.replaceAll(RegExp(r'\s+'),'');
      final isPark=nameText.startsWith('박성호') ||
          RegExp(r'(^|[^0-9])100([^0-9]|$)').hasMatch(receiptText);
      final boxLines=isPark ? const <String>[''] : _boxLines(row);
      final rowH=unitH*boxLines.length;
      final delivery='${row['delivery']??''}';
      final values=<String>[
        receiptText,
        '${row['name']??''}',
        '${row['zone']??''}',
        '',
        isPark ? '' : '${row['quantity']??''}',
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
            _paintText(c,boxLines[b],br,18,bold:false,align:TextAlign.center);
          }
        }else{
          final size=i==1
              ? 24.0
              : (i==5 ? 19.0 : 22.0);
          _paintText(
            c,
            values[i],
            r,
            size,
            bold:i==0||i==1||i==2||i==4||i==5,
            align:TextAlign.center,
          );
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

  Future<void> _saveImage() async {
    if(_rows.isEmpty||_saving)return;
    setState(()=>_saving=true);
    try{
      final pageRows=_printPages();
      if(pageRows.isEmpty)return;
      final bytes=await _renderPage(pageRows.first,page:0,pages:pageRows.length);
      final name='${(_route??'LK').toUpperCase()}_${_year}_${_voyage}_CUSTOMER_LIST.png';
      final path=await FilePicker.saveFile(dialogTitle:'고객 리스트 이미지 저장',fileName:name,bytes:bytes,
        mimeType:'image/png',type:FileType.custom,allowedExtensions:const ['png']);
      if(path!=null&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('고객 리스트 이미지 저장 완료')));
    }catch(e){_fail('이미지 저장 실패: $e');}
    finally{if(mounted)setState(()=>_saving=false);}
  }

  Future<void> _savePdf() async {
    if(_rows.isEmpty||_saving)return;
    setState(()=>_saving=true);
    try{
      final pageRows=_printPages();
      final pages=pageRows.length;
      final doc=pw.Document();
      for(var p=0;p<pages;p++){
        final png=await _renderPage(pageRows[p],page:p,pages:pages);
        final image=pw.MemoryImage(png);
        doc.addPage(pw.Page(
          pageFormat:PdfPageFormat.a4,
          margin:pw.EdgeInsets.zero,
          build:(_)=>pw.Transform.scale(
            scale:1.025,
            alignment:pw.Alignment.topCenter,
            child:pw.Image(image,fit:pw.BoxFit.fill),
          ),
        ));
      }
      final bytes=await doc.save();
      final name='${(_route??'LK').toUpperCase()}_${_year}_${_voyage}_CUSTOMER_LIST.pdf';
      final path=await FilePicker.saveFile(dialogTitle:'고객 리스트 PDF 저장',fileName:name,bytes:bytes,
        mimeType:'application/pdf',type:FileType.custom,allowedExtensions:const ['pdf']);
      if(path!=null&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('고객 리스트 PDF 저장 완료')));
    }catch(e){_fail('PDF 저장 실패: $e');}
    finally{if(mounted)setState(()=>_saving=false);}
  }

  @override
  Widget build(BuildContext context){
    final totalQty=_rows.fold<num>(0,(a,r)=>a+_num(r['quantity']));
    return Scaffold(
      appBar:AppBar(title:const Text('고객 리스트')),
      body:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(8,8,8,8),child:Column(children:[
        Row(children:[
          Expanded(flex:4,child:_selector<String>(label:'운송 경로',value:_route,items:_routes,text:(v)=>v,onChanged:(v){
            setState((){_route=v;_year=_years.isNotEmpty?_years.first:null;_voyage=_voyages.isNotEmpty?_voyages.first:null;});_loadRows();})),
          const SizedBox(width:6),
          Expanded(flex:3,child:_selector<int>(label:'년도',value:_year,items:_years,text:(v)=>'$v년',onChanged:(v){
            setState((){_year=v;_voyage=_voyages.isNotEmpty?_voyages.first:null;});_loadRows();})),
          const SizedBox(width:6),
          Expanded(flex:3,child:_selector<String>(label:'항차',value:_voyage,items:_voyages,text:(v)=>v.endsWith('항차')?v:'$v항차',onChanged:(v){setState(()=>_voyage=v);_loadRows();})),
        ]),
        const SizedBox(height:6),
        Row(children:[
          Text('고객 ${_rows.length}명',style:const TextStyle(fontWeight:FontWeight.w800)),
          const Spacer(),
          IconButton(visualDensity:VisualDensity.compact,tooltip:'새로고침',onPressed:_loading?null:_loadRows,icon:const Icon(Icons.refresh)),
        ]),
        const Divider(height:1),
        Expanded(child:_loading?const Center(child:CircularProgressIndicator()):ListView.separated(
          itemCount:_rows.length,separatorBuilder:(_,__)=>const Divider(height:1),
          itemBuilder:(context,i){
            final r=_rows[i], note='${r['note']??''}';
            return ListTile(dense:true,contentPadding:const EdgeInsets.symmetric(horizontal:4),
              leading:SizedBox(width:66,child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
                Text('${r['receipt']}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w900)),
                Text('Zone ${r['zone']}',style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700)),
              ])),
              title:Text('${r['name']}',style:const TextStyle(fontWeight:FontWeight.w800)),
              subtitle:Text([if('${r['phone']}'.isNotEmpty)'${r['phone']}','수량 ${r['quantity']}',if(note.isNotEmpty)note].join(' · '),
                maxLines:2,overflow:TextOverflow.ellipsis),
              trailing:IconButton(tooltip:'영수증 번호 / Zone 수정',onPressed:()=>_edit(r),icon:const Icon(Icons.edit_outlined,size:20)));
          })),
        Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
          child:Text('현재 항차 · 고객 ${_rows.length}명 · 총 수량 $totalQty',textAlign:TextAlign.center,
            style:const TextStyle(fontWeight:FontWeight.w800))),
        Row(children:[
          Expanded(child:OutlinedButton.icon(onPressed:_rows.isEmpty||_saving?null:_saveImage,
            icon:const Icon(Icons.image_outlined),label:const Text('이미지 저장'))),
          const SizedBox(width:8),
          Expanded(child:FilledButton.icon(onPressed:_rows.isEmpty||_saving?null:_savePdf,
            icon:const Icon(Icons.picture_as_pdf_outlined),label:Text(_saving?'생성 중...':'PDF 저장 / 프린트'))),
        ]),
      ]))),
    );
  }
}
