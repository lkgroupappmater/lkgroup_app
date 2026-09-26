import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/waybill_intake_text.dart';
import '../services/domestic_tracking_service.dart';
import '../services/waybill_intake_service.dart';

class WaybillIntakeScreen extends StatefulWidget {
  const WaybillIntakeScreen({super.key, required this.language, this.files = const [], this.fixedLink});
  final AppLanguage language;
  final List<IntakeFile> files;
  final Map<String,dynamic>? fixedLink;
  @override
  State<WaybillIntakeScreen> createState() => _WaybillIntakeScreenState();
}
class _IntakeDraft {
  _IntakeDraft(Map<String,dynamic> row, this.fileIndex, this.fileId, this.photo, this.candidates, this.target, this.kind, this.service)
    : number=TextEditingController(text:'${row['tracking_number']??''}'), name=TextEditingController(text:'${row['receiver_name']??''}'), phone=TextEditingController(text:'${row['receiver_phone']??''}'), carrier='${row['carrier']??''}', note='${row['note']??''}';
  final TextEditingController number,name,phone;
  final int fileIndex;
  final String fileId;
  String photo;
  String carrier,note,target,kind,service;
  List<Map<String,dynamic>> candidates;
  bool confirmed=false;
  void dispose(){number.dispose();name.dispose();phone.dispose();}
}
class _WaybillIntakeScreenState extends State<WaybillIntakeScreen> {
  String? _owner,_message;
  bool _busy=false;
  Map<String,dynamic>? _batch;
  List<IntakeFile> _files=[];
  final _drafts=<_IntakeDraft>[];
  final _uploaded=<String>{};
  String t(String key)=>intakeText(widget.language,key);
  bool get valid=>mounted&&DomesticTrackingService.currentUserId==_owner;
  String error(Object e)=>t(e is DomesticTrackingException?e.code:'error');
  @override
  void initState(){super.initState();_owner=DomesticTrackingService.currentUserId;if(widget.files.isNotEmpty)WidgetsBinding.instance.addPostFrameCallback((_)=>_start(widget.files));}
  @override
  void dispose(){for(final d in _drafts){d.dispose();}super.dispose();}
  Future<void> _pick() async {try{final files=await WaybillIntakeService.pick();if(valid&&files.isNotEmpty)await _start(files);}catch(e){if(valid)setState(()=>_message=error(e));}}
  Future<void> _start(List<IntakeFile> files) async {
    if(_busy||_batch!=null)return;
    setState(()=>_busy=true);
    try{
      WaybillIntakeService.validate(files);_files=files;
      _batch=await WaybillIntakeService.begin(files,'waybill');
      for(var i=0;i<files.length;i++){
        if(!valid)return;setState(()=>_message='${t('loading')} ${i+1}/${files.length}');
        await _scan(i);if(valid)setState((){});
      }
      if(valid){final refreshed=await WaybillIntakeService.call('preview',{'batch_id':_batch!['batch_id']});for(final d in _drafts){for(final p in refreshed['photos'] as List){if(p['file_id']==d.fileId)d.photo='${p['url']}';}}}
      if(valid)setState(()=>_message='${t('pending')} · ${_drafts.length}');
    }catch(e){if(valid)setState(()=>_message=error(e));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _scan(int i) async {
    final upload=Map<String,dynamic>.from(_batch!['files'][i]);final id='${upload['id']}';
    List<dynamic> found=[];String photo='',note='';
    try{
      if(!_uploaded.contains(id)){await WaybillIntakeService.upload(_files[i],upload);_uploaded.add(id);}
      final verified=await WaybillIntakeService.call('verify',{'batch_id':_batch!['batch_id'],'file_id':id});photo='${verified['photo_url']}';
      final r=await WaybillIntakeService.call('scan',{'batch_id':_batch!['batch_id'],'file_id':id});found=r['waybills'] as List;
    }catch(e){note=error(e);}
    if(!valid)return;
    if(found.isEmpty)found=[{'note':note.isEmpty?t('failed'):note}];
    final next=<_IntakeDraft>[];
    for(final raw in found){
      final w=Map<String,dynamic>.from(raw as Map);List<Map<String,dynamic>> candidates=[];
      try{
        if(widget.fixedLink!=null){candidates=[{...widget.fixedLink!,'label':[widget.fixedLink!['receiver_name'],widget.fixedLink!['statement']?['receipt_number'],widget.fixedLink!['reference']?['reference_number'],widget.fixedLink!['shipment_id']].where((v)=>v!=null).join(' · ')}];}
        else{final r=await WaybillIntakeService.call('candidates',{'receiver_name':w['receiver_name']??'','receiver_phone':w['receiver_phone']??''});candidates=(r['candidates'] as List).map((v)=>Map<String,dynamic>.from(v as Map)).toList();}
      }catch(e){w['note']=error(e);}
      final exact=candidates.where((c)=>c['exact']==true).toList();
      final target=widget.fixedLink!=null?'0':exact.length==1?'${candidates.indexOf(exact.single)}':'';
      next.add(_IntakeDraft(w,i,id,photo,candidates,target,'${widget.fixedLink?['delivery_kind']??'province'}','${widget.fixedLink?['service_kind']??'domestic'}'));
    }
    if(!valid){for(final d in next){d.dispose();}return;}
    final old=_drafts.where((d)=>d.fileIndex==i).toList();_drafts.removeWhere((d)=>d.fileIndex==i);_drafts.addAll(next);
    WidgetsBinding.instance.addPostFrameCallback((_){for(final d in old){d.dispose();}});
  }
  Future<void> _retry(_IntakeDraft d) async {setState(()=>_busy=true);try{await _scan(d.fileIndex);}finally{if(mounted)setState(()=>_busy=false);}}
  Future<void> _match(_IntakeDraft d) async {
    setState(()=>_busy=true);try{final r=await WaybillIntakeService.call('candidates',{'receiver_name':d.name.text,'receiver_phone':d.phone.text});if(valid){d.candidates=(r['candidates'] as List).map((v)=>Map<String,dynamic>.from(v as Map)).toList();d.target='';d.confirmed=false;}}
    catch(e){if(valid)_message=error(e);}finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _save() async {
    if(_busy)return;
    if(_drafts.isEmpty||_drafts.length>50||_drafts.any((d)=>!d.confirmed||d.target.isEmpty)){setState(()=>_message=t('REVIEW_REQUIRED'));return;}
    setState(()=>_busy=true);
    try{
      final entries=_drafts.map((d)=>{...(d.target=='separate'?{'link_scope':'standalone'}:d.candidates[int.parse(d.target)]),'carrier':d.carrier,'tracking_number':d.number.text.replaceAll(RegExp(r'\s'),'').toUpperCase(),'receiver_name':d.name.text,'receiver_phone':d.phone.text,'delivery_kind':d.kind,'service_kind':d.service,'file_ids':[d.fileId],'confirmed':true}).toList();
      final r=await WaybillIntakeService.call('commit',{'batch_id':_batch!['batch_id'],'entries':entries});
      if(valid)Navigator.pop(context,r);
    }catch(e){if(valid)setState(()=>_message=error(e));}finally{if(mounted)setState(()=>_busy=false);}
  }
  Widget _draft(_IntakeDraft d)=>Card(key:ObjectKey(d),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text('${d.name.text} · ${d.phone.text}',style:Theme.of(context).textTheme.titleMedium),
    if(d.photo.isNotEmpty)InkWell(onTap:()=>showDialog<void>(context:context,builder:(_)=>Dialog(child:InteractiveViewer(child:Image.network(d.photo)))),child:Image.network(d.photo,height:160,fit:BoxFit.contain,errorBuilder:(_,__,___)=>Text(t('retry')))),
    TextFormField(controller:d.number,enabled:!_busy,maxLength:40,decoration:InputDecoration(labelText:t('tracking')),onChanged:(_)=>setState(()=>d.confirmed=false)),
    DropdownButtonFormField<String>(key:ValueKey('carrier-${identityHashCode(d)}-${d.carrier}'),initialValue:d.carrier,isExpanded:true,decoration:InputDecoration(labelText:t('carrier')),items:[DropdownMenuItem(value:'',child:Text(t('selectCarrier'))),...DomesticTrackingService.carriers.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value)))],onChanged:_busy?null:(v)=>setState((){d.carrier=v??'';d.confirmed=false;})),
    TextFormField(controller:d.name,enabled:!_busy,maxLength:160,decoration:InputDecoration(labelText:t('receiver')),onChanged:(_)=>setState((){d.confirmed=false;d.target='';})),
    TextFormField(controller:d.phone,enabled:!_busy,maxLength:40,decoration:InputDecoration(labelText:t('phone')),onChanged:(_)=>setState((){d.confirmed=false;d.target='';})),
    DropdownButtonFormField<String>(key:ValueKey('target-${identityHashCode(d)}-${d.target}-${d.candidates.length}'),initialValue:d.target,isExpanded:true,decoration:InputDecoration(labelText:t('match')),items:[DropdownMenuItem(value:'',child:Text(t('unmatched'))),for(var i=0;i<d.candidates.length;i++)DropdownMenuItem(value:'$i',child:Text('${d.candidates[i]['label']}',maxLines:2,overflow:TextOverflow.ellipsis)),DropdownMenuItem(value:'separate',child:Text(t('separate')))],onChanged:_busy?null:(v)=>setState((){d.target=v??'';d.confirmed=false;})),
    DropdownButtonFormField<String>(initialValue:d.kind,decoration:InputDecoration(labelText:t('kind')),items:[DropdownMenuItem(value:'province',child:Text(t('province'))),DropdownMenuItem(value:'city',child:Text(t('city')))],onChanged:_busy?null:(v)=>setState((){d.kind=v!;d.confirmed=false;})),
    if(d.note.isNotEmpty)Text(d.note),
    CheckboxListTile(contentPadding:EdgeInsets.zero,value:d.confirmed,title:Text(t('reviewed')),onChanged:_busy?null:(v)=>setState(()=>d.confirmed=v??false)),
    Wrap(spacing:8,children:[TextButton(onPressed:_busy?null:()=>_match(d),child:Text(t('search'))),TextButton(onPressed:_busy?null:()=>_retry(d),child:Text(t('retry'))),TextButton(onPressed:_busy?null:(){setState(()=>_drafts.remove(d));WidgetsBinding.instance.addPostFrameCallback((_)=>d.dispose());},child:Text(t('removeWaybill')))]),
  ])));
  @override
  Widget build(BuildContext context){
    final sorted=[..._drafts]..sort((a,b)=>('${a.name.text}|${a.phone.text}').compareTo('${b.name.text}|${b.phone.text}'));
    final groups=<String,List<_IntakeDraft>>{};for(final d in sorted){groups.putIfAbsent('${d.name.text} · ${d.phone.text}',()=>[]).add(d);}
    return Scaffold(appBar:AppBar(title:Text(t('auto'))),body:ListView(padding:const EdgeInsets.all(16),children:[Text(t('limits')),Text(t('review')),if(_batch==null)OutlinedButton(onPressed:_busy?null:_pick,child:Text(t('pick'))),if(_busy)const LinearProgressIndicator(),if(_message!=null)Text(_message!),for(final group in groups.entries)...[Text('${group.key} (${group.value.length})',style:Theme.of(context).textTheme.titleLarge),...group.value.map(_draft)],const SizedBox(height:16),FilledButton(onPressed:_busy||_drafts.isEmpty?null:_save,child:Text('${t('confirm')} (${_drafts.length})'))]));
  }
}
