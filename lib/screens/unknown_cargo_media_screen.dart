import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/waybill_intake_text.dart';
import '../services/domestic_tracking_service.dart';
import '../services/waybill_intake_service.dart';

class UnknownCargoMediaScreen extends StatefulWidget {
  const UnknownCargoMediaScreen({super.key,required this.language,required this.row});
  final AppLanguage language;
  final Map<String,dynamic> row;
  @override
  State<UnknownCargoMediaScreen> createState()=>_UnknownCargoMediaScreenState();
}
class _UnknownCargoMediaScreenState extends State<UnknownCargoMediaScreen>{
  late final TextEditingController _invoice;
  String? _owner,_message;
  bool _busy=false;
  Map<String,dynamic>? _batch;
  final _photos=<Map<String,dynamic>>[];
  String t(String k)=>intakeText(widget.language,k);
  bool get valid=>mounted&&DomesticTrackingService.currentUserId==_owner;
  @override
  void initState(){super.initState();_invoice=TextEditingController(text:'${widget.row['invoice_number']??''}');_owner=DomesticTrackingService.currentUserId;}
  @override
  void dispose(){_invoice.dispose();super.dispose();}
  Future<void> _pick()async{
    if(_busy)return;setState(()=>_busy=true);
    try{
      final files=await WaybillIntakeService.pick();if(files.isEmpty)return;
      final batch=await WaybillIntakeService.begin(files,'unknown',shipmentId:(widget.row['id'] as num).toInt());
      _photos.clear();_batch=batch;
      for(var i=0;i<files.length;i++){
        if(!valid)return;setState(()=>_message='${t('loading')} ${i+1}/${files.length}');
        final target=Map<String,dynamic>.from(batch['files'][i]);
        await WaybillIntakeService.upload(files[i],target);
        final verified=await WaybillIntakeService.call('verify',{'batch_id':batch['batch_id'],'file_id':target['id']});
        _photos.add({'file_id':target['id'],'name':files[i].name,'kind':'waybill','url':verified['photo_url']});
      }
      if(valid)setState(()=>_message=t('pending'));
    }catch(e){_batch=null;if(valid)setState(()=>_message=t(e is DomesticTrackingException?e.code:'error'));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _save()async{
    if(_busy||_batch==null)return;
    if(_invoice.text.trim().isEmpty){setState(()=>_message=t('INVALID_TRACKING'));return;}
    setState(()=>_busy=true);
    try{
      await WaybillIntakeService.call('unknown_save',{'batch_id':_batch!['batch_id'],'invoice_number':_invoice.text,'expected_invoice':widget.row['invoice_number']??'','confirmed':true,'photos':_photos.map((p)=>{'file_id':p['file_id'],'kind':p['kind']}).toList()});
      if(valid)Navigator.pop(context,true);
    }catch(e){if(valid)setState(()=>_message=t(e is DomesticTrackingException?e.code:'error'));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('media'))),body:ListView(padding:const EdgeInsets.all(16),children:[
    Text('${widget.row['box_number']??''}'),Text(t('limits')),
    TextField(controller:_invoice,enabled:!_busy,maxLength:160,decoration:InputDecoration(labelText:t('tracking'))),
    OutlinedButton(onPressed:_busy?null:_pick,child:Text('${t('waybill')} / ${t('box')}')),
    if(_busy)const LinearProgressIndicator(),if(_message!=null)Text(_message!),
    for(final p in _photos)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Image.network('${p['url']}',height:150,fit:BoxFit.contain,errorBuilder:(_,__,___)=>Text(t('retry'))),Text('${p['name']}'),
      DropdownButtonFormField<String>(initialValue:'${p['kind']}',items:[DropdownMenuItem(value:'waybill',child:Text(t('waybill'))),DropdownMenuItem(value:'box',child:Text(t('box')))],onChanged:_busy?null:(v)=>setState(()=>p['kind']=v)),
    ]))),
    FilledButton(onPressed:_busy||_batch==null||_photos.isEmpty?null:_save,child:Text(t('save'))),
  ]));
}
