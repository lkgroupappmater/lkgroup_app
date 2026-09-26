import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/waybill_intake_text.dart';
import '../services/domestic_tracking_service.dart';
import '../services/waybill_intake_service.dart';

class CustomerRegistryScreen extends StatefulWidget {
 const CustomerRegistryScreen({super.key,this.language=AppLanguage.korean});
 final AppLanguage language;
 @override
 State<CustomerRegistryScreen> createState()=>_CustomerRegistryScreenState();
}
class _CustomerRegistryScreenState extends State<CustomerRegistryScreen>{
 final _search=TextEditingController();
 List<Map<String,dynamic>> _rows=[];
 bool _busy=false,_conflicts=false,_more=false;
 int _page=0,_total=0;
 String? _message,_owner;
 String t(String k)=>intakeText(widget.language,k);
 bool get valid=>mounted&&DomesticTrackingService.currentUserId==_owner;
 @override
 void initState(){super.initState();_owner=DomesticTrackingService.currentUserId;_load();}
 @override
 void dispose(){_search.dispose();super.dispose();}
 Future<void> _load()async{
  if(_busy)return;setState(()=>_busy=true);
  try{final r=await WaybillIntakeService.call('customers_list',{'page':_page,'query':_search.text,'conflicts_only':_conflicts});if(valid)setState((){_rows=(r['customers'] as List).map((v)=>Map<String,dynamic>.from(v as Map)).toList();_more=r['has_more']==true;_total=(r['total'] as num).toInt();_message=null;});}
  catch(e){if(valid)setState(()=>_message=t(e is DomesticTrackingException?e.code:'error'));}finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _edit(Map<String,dynamic> c)async{
  final number=TextEditingController(text:'${c['customer_no']}'),name=TextEditingController(text:'${c['name']}'),phone=TextEditingController(text:'${c['phone']}'),reason=TextEditingController();
  bool saving=false;String? message;
  await showDialog<void>(context:context,barrierDismissible:false,builder:(dialogContext)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
   title:Text(t('customers')),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextField(controller:number,enabled:!saving,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'ID')),
    TextField(controller:name,enabled:!saving,maxLength:160,decoration:InputDecoration(labelText:t('receiver'))),
    TextField(controller:phone,enabled:!saving,maxLength:40,decoration:InputDecoration(labelText:t('phone'))),
    TextField(controller:reason,enabled:!saving,maxLength:500,decoration:InputDecoration(labelText:t('reason'))),if(message!=null)Text(message!),
   ])),actions:[TextButton(onPressed:saving?null:()=>Navigator.pop(context),child:Text(t('close'))),FilledButton(onPressed:saving?null:()async{
    if(int.tryParse(number.text)==null||name.text.trim().isEmpty||reason.text.trim().isEmpty){update(()=>message=t('error'));return;}
    update(()=>saving=true);try{await WaybillIntakeService.call('customers_update',{'id':c['id'],'updated_at':c['updated_at'],'customer_no':int.parse(number.text),'name':name.text,'phone':phone.text,'reason':reason.text});if(dialogContext.mounted)Navigator.pop(dialogContext);await _load();}
    catch(e){if(dialogContext.mounted)update(()=>message=t(e is DomesticTrackingException?e.code:'error'));}finally{if(dialogContext.mounted)update(()=>saving=false);}
   },child:Text(t('save')))],
  )));
  number.dispose();name.dispose();phone.dispose();reason.dispose();
 }
 @override
 Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('customers'))),body:ListView(padding:const EdgeInsets.all(16),children:[
  Text(t('fixed')),TextField(controller:_search,decoration:InputDecoration(labelText:'ID / ${t('receiver')} / ${t('phone')}'),onSubmitted:(_){_page=0;_load();}),
  CheckboxListTile(contentPadding:EdgeInsets.zero,value:_conflicts,title:Text(t('conflict')),onChanged:_busy?null:(v){setState(()=>_conflicts=v??false);_page=0;_load();}),
  OutlinedButton(onPressed:_busy?null:(){_page=0;_load();},child:Text(t('search'))),if(_busy)const LinearProgressIndicator(),if(_message!=null)Text(_message!),Text('$_total'),
  for(final c in _rows)Card(child:ListTile(title:Text('${c['customer_code']} · ${c['name']}'),subtitle:Text('${c['phone']} ${c['conflict']==true?' · ${t('pending')}':''}'),trailing:TextButton(onPressed:_busy?null:()=>_edit(c),child:Text(t('edit'))))),
  Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[TextButton(onPressed:_busy||_page==0?null:(){_page--;_load();},child:Text(t('prev'))),TextButton(onPressed:_busy||!_more?null:(){_page++;_load();},child:Text(t('more')))]),
 ]));
}
