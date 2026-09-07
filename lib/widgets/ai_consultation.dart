import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_language.dart';
import '../core/app_colors.dart';
import '../config/supabase_config.dart';
import '../services/supabase_service.dart';
import '../services/ai_assistant_service.dart';
import 'content_media.dart';

class AiConsultationBubble extends StatelessWidget {
  const AiConsultationBubble({super.key,required this.language});
  final AppLanguage language;
  @override
  Widget build(BuildContext context)=>FloatingActionButton.extended(
    heroTag:'lk-ai-consultation',backgroundColor:AppColors.primary,foregroundColor:Colors.white,
    icon:const Icon(Icons.chat_bubble_outline),
    label:Text(sharedText(language,'AI 상담','AI chat','ປຶກສາ AI')),
    onPressed:()=>showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,
      builder:(_)=>AiConsultationPanel(language:language)),
  );
}

class AiConsultationPanel extends StatefulWidget {
  const AiConsultationPanel({super.key,required this.language});
  final AppLanguage language;
  @override
  State<AiConsultationPanel> createState()=>_AiConsultationPanelState();
}
class _AiConsultationPanelState extends State<AiConsultationPanel> {
  final _question=TextEditingController();
  final _scroll=ScrollController();
  List<Map<String,dynamic>> _rows=[];
  bool _busy=false,_loading=true;
  String? _error,_requestId,_requestQuestion,_identity;
  int _epoch=0;
  StreamSubscription<dynamic>? _authSubscription;
  String? get _owner=>SupabaseConfig.isConfigured?SupabaseService.client.auth.currentUser?.id:null;
  String _s(String ko,String en,String lo)=>sharedText(widget.language,ko,en,lo);
  @override
  void initState(){
    super.initState(); _identity=_owner;
    if(SupabaseConfig.isConfigured) _authSubscription=SupabaseService.client.auth.onAuthStateChange.listen((_){
      final owner=_owner; if(!mounted||owner==_identity)return;
      setState((){_identity=owner;_epoch++;_rows=[];_question.clear();_requestId=null;_requestQuestion=null;_error=null;_busy=false;_loading=false;});
      _load();
    });
    _load();
  }
  void _bottom()=>WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&_scroll.hasClients)_scroll.jumpTo(_scroll.position.maxScrollExtent);});
  Future<void> _load() async {
    if(_busy)return;
    final owner=_owner,epoch=++_epoch;
    if(owner==null){if(mounted)setState(()=>_loading=false);return;}
    if(mounted)setState(()=>_loading=true);
    try{final rows=await AiAssistantService.history();if(mounted&&owner==_owner&&epoch==_epoch){setState((){_rows=rows;_error=null;});_bottom();}}
    catch(_){if(mounted&&owner==_owner&&epoch==_epoch)setState(()=>_error=_s('상담 기록을 불러오지 못했습니다. 새로고침해 주세요.','Could not load history. Please refresh.','ໂຫຼດປະຫວັດບໍ່ສຳເລັດ. ກະລຸນາໂຫຼດໃໝ່.'));}
    finally{if(mounted&&owner==_owner&&epoch==_epoch)setState(()=>_loading=false);}
  }
  Future<void> _send() async {
    final owner=_owner,q=_question.text.trim();if(owner==null||q.isEmpty||_busy||q.length>4000)return;
    final epoch=++_epoch;
    if(_requestQuestion!=q){_requestId=contentUuid();_requestQuestion=q;}
    setState((){_busy=true;_loading=false;_error=null;});
    try{final answer=await AiAssistantService.consultDetailed(question:q,language:widget.language,requestId:_requestId);
      if(!mounted||owner!=_owner||epoch!=_epoch)return;
      setState((){_rows.removeWhere((r)=>r['id']==answer['id']);_rows.add({...answer,'question':q});_question.clear();_requestId=null;_requestQuestion=null;});_bottom();
    }catch(_){
      try { final failed = await AiAssistantService.requestFailed(_requestId); if (mounted && owner==_owner && epoch==_epoch && failed) { _requestId=null; _requestQuestion=null; } } catch (_) {}
      if(mounted&&owner==_owner&&epoch==_epoch)setState(()=>_error=_s('답변을 받지 못했습니다. 새로고침으로 완료 여부를 확인하거나 다시 시도해 주세요.','No answer received. Refresh history or try again.','ຍັງບໍ່ໄດ້ຄຳຕອບ. ໂຫຼດປະຫວັດໃໝ່ ຫຼື ລອງອີກ.'));}
    finally{if(mounted&&owner==_owner&&epoch==_epoch)setState(()=>_busy=false);}
  }
  Future<void> _source(dynamic source) async {if(source is! Map)return;final url=Uri.tryParse('${source['url']??''}');if(url!=null&&url.scheme=='https')await launchUrl(url,mode:LaunchMode.externalApplication);}
  @override
  void dispose(){_authSubscription?.cancel();_question.dispose();_scroll.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>Padding(
    padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(context).bottom),
    child:SizedBox(height:math.max(200.0, math.min(MediaQuery.sizeOf(context).height*.72, MediaQuery.sizeOf(context).height-MediaQuery.viewInsetsOf(context).bottom-MediaQuery.paddingOf(context).top-28)),child:Column(children:[
      ListTile(title:Text(_s('LK Group AI 상담','LK Group AI chat','ປຶກສາ LK Group AI')),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:_s('새로고침','Refresh','ໂຫຼດໃໝ່'),onPressed:_busy?null:_load,icon:const Icon(Icons.refresh)),IconButton(tooltip:_s('닫기','Close','ປິດ'),onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close))])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text(_s('공개된 회사 안내와 최신 공지·일정을 참고합니다. 같은 계정의 앱·웹 상담 기록이 함께 표시됩니다.','Uses published company guidance, notices and schedules. Your app and web history is shared.','ອ້າງອີງຂໍ້ມູນບໍລິສັດ, ແຈ້ງການ ແລະ ຕາຕະລາງ. ປະຫວັດແອັບ ແລະ ເວັບໃຊ້ຮ່ວມກັນ.'),style:const TextStyle(fontSize:12))),
      if(_loading) const LinearProgressIndicator(),
      Expanded(child:_owner==null?Center(child:Text(_s('로그인 후 AI 상담을 이용할 수 있습니다.','Sign in to use AI chat.','ເຂົ້າລະບົບເພື່ອໃຊ້ AI.'))):ListView(controller:_scroll,padding:const EdgeInsets.all(16),children:[
        for(final row in _rows)...[
          Align(alignment:Alignment.centerRight,child:Container(margin:const EdgeInsets.only(top:14,bottom:8),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:AppColors.primary.withValues(alpha:.08),borderRadius:BorderRadius.circular(10)),child:Text('${row['question']}'))),
          SelectableText('${row['answer']}'),
          for(final source in (row['sources'] is List?row['sources'] as List:[])) TextButton(onPressed:()=>_source(source),child:Text('${source['title']??_s('참고 자료','Source','ແຫຼ່ງຂໍ້ມູນ')}')),
        ],
      ])),
      if(_error!=null) Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:TextField(controller:_question,enabled:!_busy&&_owner!=null,maxLength:4000,minLines:1,maxLines:3,decoration:InputDecoration(hintText:_s('궁금한 내용을 입력하세요.','Ask a question.','ປ້ອນຄຳຖາມ.'),counterText:'',border:const OutlineInputBorder()))),const SizedBox(width:8),IconButton(tooltip:_s('보내기','Send','ສົ່ງ'),onPressed:_busy||_owner==null?null:_send,icon:_busy?const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send))])),
      TextButton(onPressed:()=>launchUrl(Uri.parse('https://open.kakao.com/o/sYly2bxf'),mode:LaunchMode.externalApplication),child:Text(_s('담당자에게 상담하기','Contact our team','ຕິດຕໍ່ພະນັກງານ'))),
    ])),
  );
}
