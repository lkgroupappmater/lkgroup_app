import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_language.dart';
import '../services/supabase_service.dart';

String sharedText(AppLanguage language, String ko, String en, String lo) =>
    language == AppLanguage.korean ? ko : language == AppLanguage.lao ? lo : en;

List<Map<String, dynamic>> contentAttachments(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

String contentUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}

Future<String> contentMediaUrl(Map<String, dynamic> item, String bucket) async {
  final external = Uri.tryParse('${item['url'] ?? ''}');
  if (external != null && external.scheme == 'https' && external.host.isNotEmpty) return external.toString();
  return SupabaseService.client.storage.from(bucket).createSignedUrl('${item['path']}', 60);
}

class ContentMediaEditor extends StatefulWidget {
  const ContentMediaEditor({super.key, required this.items, required this.kind, required this.language, required this.onBusy});
  final List<Map<String, dynamic>> items;
  final String kind;
  final AppLanguage language;
  final ValueChanged<bool> onBusy;
  @override
  State<ContentMediaEditor> createState() => _ContentMediaEditorState();
}

class _ContentMediaEditorState extends State<ContentMediaEditor> {
  bool _busy = false;
  String? _error;
  String _s(String ko,String en,String lo)=>sharedText(widget.language,ko,en,lo);
  Future<void> _add() async {
    if (_busy) return;
    setState(() { _busy=true; _error=null; }); widget.onBusy(true);
    try {
      if (widget.items.length>=12) throw StateError(_s('최대 12개까지 첨부할 수 있습니다.','Up to 12 attachments.','ແນບໄດ້ສູງສຸດ 12 ໄຟລ໌.'));
      final file = await FilePicker.pickFile(type:FileType.custom,allowedExtensions:['jpg','jpeg','png','webp','pdf']);
      if(file==null) return;
      final bytes=await file.readAsBytes();
      final ext=file.name.split('.').last.toLowerCase();
      final mime={'jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png','webp':'image/webp','pdf':'application/pdf'}[ext];
      if(mime==null||bytes.isEmpty||bytes.length>20*1024*1024) throw StateError(_s('파일당 20 MB 이하로 선택하세요.','Choose files up to 20 MB.','ເລືອກໄຟລ໌ບໍ່ເກີນ 20 MB.'));
      final owner=SupabaseService.client.auth.currentUser?.id;
      if(owner==null) throw StateError('Login required');
      final path='$owner/${widget.kind}/${contentUuid()}_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_')}';
      await SupabaseService.client.storage.from('content-media').uploadBinary(path,bytes,fileOptions:FileOptions(contentType:mime));
      if(!mounted||owner!=SupabaseService.client.auth.currentUser?.id) return;
      setState(()=>widget.items.add({'path':path,'name':file.name,'mime':mime,'caption':''}));
    } catch(error) { if(mounted) setState(()=>_error='$error'); }
    finally { if(mounted) {setState(()=>_busy=false);widget.onBusy(false);} }
  }
  @override
  Widget build(BuildContext context) => Padding(
    padding:const EdgeInsets.only(top:14),
    child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      OutlinedButton.icon(onPressed:_busy?null:_add,icon:const Icon(Icons.attach_file),label:Text(_s('사진·전단지·PDF 추가','Add photo, flyer or PDF','ເພີ່ມຮູບ, ໃບປິວ ຫຼື PDF'))),
      Text(_s('최대 12개 · 파일당 20 MB · 저장하면 앱과 웹에 반영됩니다.','12 files · 20 MB each · Save to update the app and website.','12 ໄຟລ໌ · 20 MB ຕໍ່ໄຟລ໌ · ບັນທຶກເພື່ອອັບເດດແອັບ ແລະ ເວັບ.'),style:const TextStyle(fontSize:12)),
      if(_busy) const LinearProgressIndicator(),
      for(var i=0;i<widget.items.length;i++) Padding(
        key:ValueKey(widget.items[i]['path']),padding:const EdgeInsets.symmetric(vertical:6),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${i+1}. ${widget.items[i]['name']}'),
          TextFormField(initialValue:'${widget.items[i]['caption']??''}',enabled:!_busy,onChanged:(v)=>widget.items[i]['caption']=v,decoration:InputDecoration(labelText:_s('사진·자료 설명','Caption','ຄຳອະທິບາຍ'))),
          Row(children:[IconButton(tooltip:_s('위로','Move up','ຍ້າຍຂຶ້ນ'),onPressed:_busy||i==0?null:()=>setState((){final item=widget.items.removeAt(i);widget.items.insert(i-1,item);}),icon:const Icon(Icons.arrow_upward)),TextButton(onPressed:_busy?null:()=>setState(()=>widget.items.removeAt(i)),child:Text(_s('첨부 제외','Remove','ເອົາອອກ')))])
        ])),
      if(_error!=null) Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ]),
  );
}

class ContentMediaGallery extends StatelessWidget {
  const ContentMediaGallery({super.key,required this.items,required this.language,this.bucket='content-media',this.coverOnly=false});
  final List<Map<String,dynamic>> items;
  final AppLanguage language;
  final String bucket;
  final bool coverOnly;
  Future<void> _open(BuildContext context,Map<String,dynamic> item) async {
    try {
      final url=await contentMediaUrl(item,bucket);
      if(!context.mounted) return;
      if('${item['mime']}'.startsWith('image/')) {
        await showDialog<void>(context:context,builder:(dialogContext)=>Dialog(child:Stack(children:[
          InteractiveViewer(minScale:0.5,maxScale:5,child:Image.network(url,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image))),
          Positioned(top:0,right:0,child:IconButton(tooltip:sharedText(language,'닫기','Close','ປິດ'),onPressed:()=>Navigator.pop(dialogContext),icon:const Icon(Icons.close))),
        ])));
      } else { if(!await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication)) throw StateError('Cannot open file'); }
    } catch(error) {if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));}
  }
  @override
  Widget build(BuildContext context) {
    final visible=coverOnly?items.where((a)=>'${a['mime']}'.startsWith('image/')).take(1).toList():items;
    return Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:visible.map((a)=>Padding(
      padding:const EdgeInsets.only(top:10),child:FutureBuilder<String>(future:contentMediaUrl(a,bucket),builder:(context,snapshot){
        final caption='${a['caption']??''}';
        return Column(mainAxisSize:MainAxisSize.min,children:[
          InkWell(onTap:()=>_open(context,a),child:'${a['mime']}'.startsWith('image/')
            ? ClipRRect(borderRadius:BorderRadius.circular(8),child:snapshot.hasData?Image.network(snapshot.data!,height:coverOnly?110:null,fit:BoxFit.contain,semanticLabel:caption,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image)):const Padding(padding:EdgeInsets.all(12),child:Icon(Icons.image_outlined)))
            : ListTile(leading:const Icon(Icons.picture_as_pdf),title:Text('${a['name']}'),trailing:const Icon(Icons.open_in_new))),
          if(caption.isNotEmpty&&!coverOnly) Padding(padding:const EdgeInsets.only(top:5),child:Text(caption,style:const TextStyle(fontSize:12))),
        ]);
      }),
    )).toList());
  }
}
