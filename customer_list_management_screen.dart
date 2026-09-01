import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:supabase_flutter/supabase_flutter.dart';

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
      final raw=await Supabase.instance.client.from('shipments')
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
      final raw=await Supabase.instance.client.from('shipments').select(
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
        result.add({
          'receipt':e.key,'name':'${first['consignee_name']??''}'.trim(),
          'phone':'${first['consignee_phone']??''}'.trim(),'zone':'${first['unloading_zone']??''}'.trim(),
          'note':notes,'rows':e.value.length,'quantity':qty,
        });
      }
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
      await Supabase.instance.client.from('shipments').update({
        'receipt_number':nr,'unloading_zone':nz,
      }).eq('route',_route!).eq('shipment_year',_year!).eq('voyage',_voyage!)
       .eq('receipt_number','${r['receipt']}').isFilter('deletion_requested_at',null);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('영수증 번호 / Zone 수정 완료')));
      await _loadRows();
    }catch(e){_fail('수정 실패: $e');}
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
    return '$route ${_year ?? ''} ${_voyage ?? ''}항차 고객 리스트';
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
    const w=1600.0, topH=72.0, headerH=82.0, colH=48.0, rowH=38.0, footerH=42.0;
    final h=topH+headerH+colH+rowH*rows.length+footerH;
    final rec=ui.PictureRecorder(); final c=Canvas(rec);
    c.drawRect(Rect.fromLTWH(0,0,w,h),Paint()..color=Colors.white);
    final line=Paint()..color=const Color(0xFF7890A4)..style=PaintingStyle.stroke..strokeWidth=1;
    final fill=Paint()..color=const Color(0xFFE7F0F7);
    _paintText(c,_title,Rect.fromLTWH(0,topH+8,w,52),30,bold:true);
    _paintText(c,'${_rows.length}명  ·  ${page+1}/$pages',Rect.fromLTWH(0,topH+52,w,25),14);
    final y0=topH+headerH;
    final xs=<double>[0,150,500,790,970,1120,1600];
    final heads=['영수증 번호','고객명/회사명','연락처','구획(Zone)','수량','비고'];
    for(var i=0;i<heads.length;i++){
      final r=Rect.fromLTRB(xs[i],y0,xs[i+1],y0+colH);
      c.drawRect(r,fill); c.drawRect(r,line); _paintText(c,heads[i],r,17,bold:true);
    }
    for(var n=0;n<rows.length;n++){
      final row=rows[n]; final y=y0+colH+n*rowH;
      final vals=['${row['receipt']}','${row['name']}','${row['phone']}','${row['zone']}',
        '${row['quantity']}','${row['note']}'];
      for(var i=0;i<vals.length;i++){
        final r=Rect.fromLTRB(xs[i],y,xs[i+1],y+rowH);
        c.drawRect(r,line);
        _paintText(c,vals[i],r,i==0||i==3?16:14,bold:i==0||i==3,
          align:(i==1||i==5)?TextAlign.left:TextAlign.center);
      }
    }
    final fy=y0+colH+rows.length*rowH;
    _paintText(c,'LK GROUP · 고객 리스트 관리 출력',Rect.fromLTWH(0,fy,w,footerH),13);
    final pic=rec.endRecording(); final img=await pic.toImage(w.toInt(),h.toInt());
    final bd=await img.toByteData(format:ui.ImageByteFormat.png);
    if(bd==null)throw StateError('PNG 생성 실패');
    return bd.buffer.asUint8List();
  }

  Future<void> _saveImage() async {
    if(_rows.isEmpty||_saving)return;
    setState(()=>_saving=true);
    try{
      final bytes=await _renderPage(_rows,page:0,pages:1);
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
      const perPage=30;
      final pages=(_rows.length/perPage).ceil();
      final doc=pw.Document();
      for(var p=0;p<pages;p++){
        final slice=_rows.skip(p*perPage).take(perPage).toList(growable:false);
        final png=await _renderPage(slice,page:p,pages:pages);
        final image=pw.MemoryImage(png);
        doc.addPage(pw.Page(pageFormat:PdfPageFormat.a4.landscape,margin:const pw.EdgeInsets.all(10),
          build:(_)=>pw.Center(child:pw.Image(image,fit:pw.BoxFit.contain))));
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
