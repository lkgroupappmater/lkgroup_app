import 'package:flutter/material.dart';
import '../core/route_catalog.dart';
import '../services/route_development_service.dart';

class AdditionalFeatureDevelopmentScreen extends StatefulWidget {
  const AdditionalFeatureDevelopmentScreen({super.key});
  @override State<AdditionalFeatureDevelopmentScreen> createState()=>_State();
}
class _State extends State<AdditionalFeatureDevelopmentScreen>{
  List<Map<String,dynamic>> rows=[]; String? selected; bool loading=true;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async { try{rows=await RouteDevelopmentService.instance.listRoutes();}catch(e){if(mounted)_msg('$e');}
    if(mounted)setState(()=>loading=false);}
  void _msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  @override Widget build(BuildContext c)=>Scaffold(
    appBar:AppBar(title:const Text('추가 기능 개발')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Text('운송 경로 BASE / 공통 운임 관리',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(value:selected,decoration:const InputDecoration(labelText:'운송 경로 선택',border:OutlineInputBorder()),
        items:rows.where((e)=>e['status']=='active').map((e)=>DropdownMenuItem(value:'${e['route_key']}',child:Text('${e['display_name']}'))).toList(),
        onChanged:(v)=>setState(()=>selected=v)),
      const SizedBox(height:12),
      Row(children:[
        Expanded(child:FilledButton.icon(onPressed:selected==null?null:()=>_openEdit(false),icon:const Icon(Icons.edit),label:const Text('편집'))),
        const SizedBox(width:8),
        Expanded(child:OutlinedButton.icon(onPressed:()=>_openEdit(true),icon:const Icon(Icons.add),label:const Text('신규 운송 경로 추가'))),
      ]),
      const SizedBox(height:16),
      const Card(child:Padding(padding:EdgeInsets.all(12),child:Text(
        '여기서 저장한 운임은 DB freight_rate_tiers가 원본이 되며 가견적·명세서·화물 운임 계산이 같은 기준을 사용합니다.'
      ))),
    ]),
  );
  Future<void> _openEdit(bool create) async{
    Map<String,dynamic>? route;
    if(!create) route=rows.firstWhere((e)=>'${e['route_key']}'==selected);
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>RouteDefinitionEditorScreen(route:route,allRoutes:rows)));
    await _load();
  }
}

class RouteDefinitionEditorScreen extends StatefulWidget{
  const RouteDefinitionEditorScreen({super.key,this.route,required this.allRoutes});
  final Map<String,dynamic>? route; final List<Map<String,dynamic>> allRoutes;
  @override State<RouteDefinitionEditorScreen> createState()=>_EditorState();
}
class _EditorState extends State<RouteDefinitionEditorScreen>{
  late final TextEditingController title,company,phone,address,box,receipt,factor,minimum;
  List<Map<String,dynamic>> tiers=[]; String? base; bool savedDraft=false,busy=false;
  bool get create=>widget.route==null;
  @override void initState(){super.initState(); final r=widget.route??{};
    title=TextEditingController(text:'${r['display_name']??''}'); company=TextEditingController(text:'${r['company_name']??''}');
    phone=TextEditingController(text:'${r['phone']??''}'); address=TextEditingController(text:'${r['address']??''}');
    box=TextEditingController(text:'${r['box_prefix']??''}'); receipt=TextEditingController(text:'${r['receipt_prefix']??''}');
    factor=TextEditingController(text:'${r['volumetric_factor']??0.00022}'); minimum=TextEditingController(text:'${r['minimum_charge']??0}');
    if(!create){base='${r['route_key']}';_rates();}
  }
  Future<void> _rates()async{tiers=await RouteDevelopmentService.instance.rates(base!);if(mounted)setState((){});}
  List<Map<String,double>> _tierData()=>tiers.map((e)=><String,double>{'min_weight_kg':double.tryParse('${e['min_weight_kg']}')??0,'rate_per_kg':double.tryParse('${e['rate_per_kg']}')??0}).toList();
  void _addTier()=>setState(()=>tiers.add({'min_weight_kg':0.0,'rate_per_kg':0.0}));
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:Text(create?'신규 운송 경로':'운송 경로 편집')),
   body:ListView(padding:const EdgeInsets.all(14),children:[
    if(create) DropdownButtonFormField<String>(value:base,decoration:const InputDecoration(labelText:'기반 BASE 운송 경로',border:OutlineInputBorder()),
      items:widget.allRoutes.where((e)=>e['status']=='active').map((e)=>DropdownMenuItem(value:'${e['route_key']}',child:Text('${e['display_name']}'))).toList(),
      onChanged:(v)async{base=v;if(v!=null){final r=widget.allRoutes.firstWhere((e)=>'${e['route_key']}'==v);company.text='${r['company_name']??''}';phone.text='${r['phone']??''}';address.text='${r['address']??''}';box.text='${r['box_prefix']??''}';receipt.text='${r['receipt_prefix']??''}';factor.text='${r['volumetric_factor']??.00022}';minimum.text='${r['minimum_charge']??0}';await _rates();}}},
    if(create) const SizedBox(height:10),
    _f(title,'운송 경로 타이틀'),const SizedBox(height:8),_f(company,'회사명'),const SizedBox(height:8),_f(phone,'전화번호'),
    const SizedBox(height:8),_f(address,'주소'),const SizedBox(height:8),Row(children:[Expanded(child:_f(box,'박스 Prefix')),const SizedBox(width:8),Expanded(child:_f(receipt,'영수번호 Prefix'))]),
    const SizedBox(height:8),Row(children:[Expanded(child:_f(factor,'부피중량 계수')),const SizedBox(width:8),Expanded(child:_f(minimum,'최소 운임 USD'))]),
    const SizedBox(height:16),Row(children:[const Expanded(child:Text('단가 구조',style:TextStyle(fontWeight:FontWeight.w800))),TextButton.icon(onPressed:_addTier,icon:const Icon(Icons.add),label:const Text('구간 추가'))]),
    ...List.generate(tiers.length,(i)=>Card(child:Padding(padding:const EdgeInsets.all(8),child:Row(children:[
      Expanded(child:TextFormField(initialValue:'${tiers[i]['min_weight_kg']}',decoration:const InputDecoration(labelText:'이상 kg'),onChanged:(v)=>tiers[i]['min_weight_kg']=double.tryParse(v)??0)),
      const SizedBox(width:8),Expanded(child:TextFormField(initialValue:'${tiers[i]['rate_per_kg']}',decoration:const InputDecoration(labelText:'USD/kg'),onChanged:(v)=>tiers[i]['rate_per_kg']=double.tryParse(v)??0)),
      IconButton(onPressed:()=>setState(()=>tiers.removeAt(i)),icon:const Icon(Icons.delete_outline))
    ])))),
    const SizedBox(height:16),Row(children:[
      Expanded(child:OutlinedButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('취소'))),const SizedBox(width:8),
      Expanded(child:FilledButton(style:savedDraft?FilledButton.styleFrom(backgroundColor:Colors.green):null,onPressed:busy?null:_save,
        child:Text(savedDraft?'신규 경로 적용':create?'내용 저장 (아직 적용 안됨)':'내용 저장')))
    ])
   ]));
  Widget _f(TextEditingController c,String l)=>TextField(controller:c,decoration:InputDecoration(labelText:l,border:const OutlineInputBorder()));
  Future<void> _save()async{
    if(title.text.trim().isEmpty||tiers.isEmpty||(create&&base==null)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('운송 경로, 기반 BASE, 단가를 확인해 주세요.')));return;}
    if(savedDraft){
      final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('신규 운송 경로 적용'),content:const Text('작성하신 데이터를 기반으로 신규 운송 경로가 추가 됩니다.'),actions:[
        TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('취소')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('확인'))]))??false;
      if(!ok)return; setState(()=>busy=true);
      try{await RouteDevelopmentService.instance.applyDraft(base!);if(mounted)Navigator.pop(context);}finally{if(mounted)setState(()=>busy=false);} return;
    }
    setState(()=>busy=true);
    try{
      if(create){base=await RouteDevelopmentService.instance.createDraft(label:title.text.trim(),baseRouteKey:base!,company:company.text,phone:phone.text,address:address.text,boxPrefix:box.text,receiptPrefix:receipt.text,volumetricFactor:double.tryParse(factor.text)??.00022,minimumCharge:double.tryParse(minimum.text)??0,tiers:_tierData());if(mounted)setState(()=>savedDraft=true);}
      else{await RouteDevelopmentService.instance.saveExisting(key:'${widget.route!['route_key']}',label:title.text.trim(),company:company.text,phone:phone.text,address:address.text,boxPrefix:box.text,receiptPrefix:receipt.text,volumetricFactor:double.tryParse(factor.text)??.00022,minimumCharge:double.tryParse(minimum.text)??0,tiers:_tierData());if(mounted)Navigator.pop(context);}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}finally{if(mounted)setState(()=>busy=false);}
  }
}
