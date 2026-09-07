import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../services/content_service.dart';
import '../widgets/content_media.dart';

class CompanyContentScreen extends StatefulWidget {
  const CompanyContentScreen({super.key,required this.language});
  final AppLanguage language;
  @override
  State<CompanyContentScreen> createState()=>_CompanyContentScreenState();
}
class _CompanyContentScreenState extends State<CompanyContentScreen> {
  late Future<List<Map<String,dynamic>>> _future;
  String _category='all',_query='';
  String _s(String ko,String en,String lo)=>sharedText(widget.language,ko,en,lo);
  Map<String,String> get _categories=>{'all':_s('전체','All','ທັງໝົດ'),'company':_s('회사 소개','Company','ບໍລິສັດ'),'case':_s('주요 실적','Projects','ຜົນງານ'),'activity':_s('기업 활동','Activities','ກິດຈະກຳ'),'csr':'LifeTogether CSR','media':_s('뉴스·자료실','News / resources','ຂ່າວ / ຂໍ້ມູນ'),'guide':_s('고객 이용 안내','Customer guides','ຄຳແນະນຳລູກຄ້າ'),'service':_s('서비스 안내','Services','ບໍລິການ')};
  @override
  void initState(){super.initState();_future=ContentService.fetchCompanyArticles(language:widget.language);}
  Future<void> _detail(Map<String,dynamic> row)=>showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
    title:Text('${row['title']}'),
    content:SizedBox(width:500,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(row['original_published_at']!=null) Text('${row['original_published_at']}',style:const TextStyle(fontSize:12)),
      SelectableText('${row['summary']??''}'),const SizedBox(height:12),SelectableText('${row['body']??''}'),
      ContentMediaGallery(items:contentAttachments(row['attachments']),language:widget.language,bucket:'website-content'),
      for(final source in contentAttachments(row['sources'])) TextButton(onPressed:(){final uri=Uri.tryParse('${source['url']}');if(uri!=null&&['http','https'].contains(uri.scheme))launchUrl(uri,mode:LaunchMode.externalApplication);},child:Text(_s('원문 보기','View source','ເບິ່ງຕົ້ນສະບັບ'))),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:Text(_s('닫기','Close','ປິດ')))],
  ));
  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:AppColors.background,
    appBar:AppBar(title:Text(_s('회사 소개·활동·자료실','Company / activities / resources','ບໍລິສັດ / ກິດຈະກຳ / ຂໍ້ມູນ')),backgroundColor:AppColors.primary,foregroundColor:Colors.white),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(14),child:Column(children:[
        DropdownButtonFormField<String>(initialValue:_category,isExpanded:true,items:_categories.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>setState(()=>_category=v??'all')),
        TextField(decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:_s('제목·내용 검색','Search title or content','ຄົ້ນຫາຫົວຂໍ້ ຫຼື ເນື້ອຫາ')),onChanged:(v)=>setState(()=>_query=v.trim().toLowerCase())),
      ])),
      Expanded(child:FutureBuilder<List<Map<String,dynamic>>>(future:_future,builder:(context,snapshot){
        if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError)return Center(child:TextButton(onPressed:()=>setState(()=>_future=ContentService.fetchCompanyArticles(language:widget.language)),child:Text(_s('다시 불러오기','Retry','ລອງອີກ'))));
        final rows=(snapshot.data??[]).where((r){final tags=((r['tags'] as List?) ?? []).map((t)=>'$t'.toLowerCase()).toList();return (_category=='all'||r['category']==_category||(_category=='csr'&&tags.contains('csr'))||(_category=='activity'&&tags.contains('기업 활동'))) && ('${r['title']} ${r['body']}'.toLowerCase().contains(_query));}).toList();
        return RefreshIndicator(onRefresh:()async{setState(()=>_future=ContentService.fetchCompanyArticles(language:widget.language));await _future;},child:ListView(padding:const EdgeInsets.fromLTRB(14,0,14,20),physics:const AlwaysScrollableScrollPhysics(),children:[
          if(rows.isEmpty)Padding(padding:const EdgeInsets.all(24),child:Text(_s('표시할 자료가 없습니다.','No content to display.','ບໍ່ມີເນື້ອຫາ.'))),
          for(final row in rows)Card(child:InkWell(onTap:()=>_detail(row),borderRadius:BorderRadius.circular(12),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(_categories['${row['category']}']??'',style:const TextStyle(fontSize:12,color:AppColors.textHint)),
            Text('${row['title']}',style:const TextStyle(fontWeight:FontWeight.w600)),
            ContentMediaGallery(items:contentAttachments(row['attachments']),language:widget.language,bucket:'website-content',coverOnly:true),
            const SizedBox(height:8),Text('${row['summary']??''}'),
          ])))),
        ]));
      })),
    ]),
  );
}
