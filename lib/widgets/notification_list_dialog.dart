import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/cargo_ui_strings.dart';

String notificationText(AppLanguage l, String ko, String en, String lo) =>
    l == AppLanguage.korean ? ko : l == AppLanguage.lao ? lo : en;

List<String> notificationDetails(Map<String, dynamic> row, AppLanguage language) {
  String value(dynamic v) => v == null || v == '' ? '—' : v is Map || v is List ? jsonEncode(v) : '$v';
  final r = Map<String, dynamic>.from(row['request_details'] ?? {});
  final q = Map<String, dynamic>.from(row['quote_details'] ?? {});
  final changes = <String, dynamic>{...Map<String, dynamic>.from(r['changes'] ?? {}), ...Map<String, dynamic>.from(r['admin_changes'] ?? {})};
  final before = Map<String, dynamic>.from(r['before_values'] ?? {});
  const labels = {'consignee_name':'수취인 이름 / 회사명','consignee_phone':'연락처','phone':'연락처','receipt_number':'영수번호','invoice_number':'송장번호','box_number':'박스번호','weight_kg':'중량 (kg)','length_cm':'가로 (cm)','width_cm':'세로 (cm)','height_cm':'높이 (cm)','note':'비고','remark':'비고','route':'운송 경로','year':'년도','voyage':'항차','quantity':'화물개수','zone':'Zone'};
  final heading = r['status'] == 'rejected'
      ? notificationText(language,'요청 내용 (거절)','Requested changes (rejected)','ຄຳຂໍປ່ຽນແປງ (ປະຕິເສດ)')
      : notificationText(language,'변경 내용','Change details','ລາຍລະອຽດການປ່ຽນແປງ');
  return [
    if (r.isNotEmpty) [r['receipt_number'],r['invoice_number'],r['consignee_name']].where((v)=>v != null && '$v'.isNotEmpty).join(' · '),
    if (changes.isNotEmpty) heading,
    for (final e in changes.entries) '${CargoUiStrings.get(language,labels[e.key] ?? e.key)}: ${before.containsKey(e.key) ? '${value(before[e.key])} → ' : ''}${value(e.value)}',
    if ('${r['review_result'] ?? ''}'.isNotEmpty) '${r['review_result']}',
    if (q.isNotEmpty) [q['subject'],q['customer_name'],q['route'],q['contact']].where((v)=>v != null && '$v'.isNotEmpty).join(' · '),
    if ('${q['content'] ?? ''}'.isNotEmpty) '${q['content']}',
  ].where((v)=>v.isNotEmpty).toList();
}

/// The list route stays mounted while onOpen shows a separate detail dialog.
class NotificationListDialog extends StatefulWidget {
  const NotificationListDialog({super.key, required this.language, required this.initial,
    required this.onOpen, required this.onReadAll, required this.loadPage,
    required this.isCurrentOwner, this.header});
  final AppLanguage language;
  final Map<String,dynamic> initial;
  final Future<void> Function(Map<String,dynamic>) onOpen;
  final Future<Map<String,dynamic>> Function(int,String) onReadAll;
  final Future<Map<String,dynamic>> Function(int) loadPage;
  final bool Function() isCurrentOwner;
  final Widget? header;
  @override
  State<NotificationListDialog> createState()=>_NotificationListDialogState();
}
class _NotificationListDialogState extends State<NotificationListDialog> {
  final _scroll=ScrollController();
  late List<Map<String,dynamic>> _rows;
  late int _throughId, _unread;
  late String? _throughAt;
  int _offset=0;
  bool _busy=false, _more=false, _completed=false;
  String? _error;
  String s(String ko,String en,String lo)=>notificationText(widget.language,ko,en,lo);
  @override
  void initState(){super.initState();_setInitial(widget.initial);}
  void _setInitial(Map<String,dynamic> data){
    _rows=List<Map<String,dynamic>>.from(data['rows'] ?? []).map((r)=>Map<String,dynamic>.from(r)).toList();
    _throughId=(data['read_through_id'] as num?)?.toInt() ?? 0;
    _throughAt=data['read_through_at'] as String?;
    _unread=(data['unread_count'] as num?)?.toInt() ?? 0;
    _more=_rows.length==50;_offset=0;_completed=false;
  }
  @override
  void dispose(){_scroll.dispose();super.dispose();}
  Future<void> _act(Future<void> Function() work) async {
    if (_busy || !widget.isCurrentOwner()) return;
    setState((){_busy=true;_error=null;});
    try{await work();}catch(e){if(mounted && widget.isCurrentOwner())setState(()=>_error='$e');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _open(Map<String,dynamic> row)=>_act(() async {
    await widget.onOpen(row);
    if(!mounted || !widget.isCurrentOwner())return;
    final data=await widget.loadPage(0);
    if(!mounted || !widget.isCurrentOwner())return;
    final page=List<Map<String,dynamic>>.from(data['rows'] ?? []);
    setState((){
      _unread=(data['unread_count'] as num?)?.toInt() ?? 0;
      for(final fresh in page){for(final old in _rows){if(old['id']==fresh['id'])old.addAll(fresh);}}
    });
  });
  Future<void> _readAll()=>_act(() async {
    if(_throughAt==null)return;
    final result=await widget.onReadAll(_throughId,_throughAt!);
    if(!mounted || !widget.isCurrentOwner())return;
    setState((){
      _unread=(result['unread_count'] as num?)?.toInt() ?? 0;_completed=true;
      for(final row in _rows){if((row['id'] as num).toInt()<=_throughId && DateTime.parse('${row['created_at']}').compareTo(DateTime.parse(_throughAt!))<=0)row['is_read']=true;}
    });
  });
  @override
  Widget build(BuildContext context)=>AlertDialog(
    title:Text('${AppStrings.get(widget.language,'notifications')} ($_unread)'),
    content:SizedBox(width:760,height:MediaQuery.sizeOf(context).height*.62,
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        Expanded(child:ListView(controller:_scroll,children:[
          if(widget.header!=null)widget.header!,
          if(_rows.isEmpty)Text(AppStrings.get(widget.language,'no_notifications')),
          for(final row in _rows)Card(key:ValueKey('notification-${row['id']}'),
            color:row['is_read']==true ? null : Theme.of(context).colorScheme.primaryContainer,
            child:InkWell(onTap:_busy ? null : ()=>_open(row),child:Padding(padding:const EdgeInsets.all(12),
              child:LayoutBuilder(builder:(context,size){
                final summary=Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('${row['is_read']==true ? '' : '● '}${row['title'] ?? ''}',style:Theme.of(context).textTheme.titleSmall),
                  Text('${row['message'] ?? ''}'),
                  Text('${row['created_at'] ?? ''}',style:Theme.of(context).textTheme.labelSmall),
                ]);
                final detail=Column(crossAxisAlignment:CrossAxisAlignment.start,children:notificationDetails(row,widget.language).map((v)=>Text(v)).toList());
                return size.maxWidth>=600 ? Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(flex:2,child:summary),const SizedBox(width:16),Expanded(flex:3,child:detail)])
                    : Column(crossAxisAlignment:CrossAxisAlignment.start,children:[summary,const SizedBox(height:8),detail]);
              })))),
          if(_more)TextButton(onPressed:_busy ? null : ()=>_act(()async{
            final data=await widget.loadPage(_offset+50);
            if(!mounted || !widget.isCurrentOwner())return;
            final page=List<Map<String,dynamic>>.from(data['rows'] ?? []);
            setState((){_offset+=50;_more=page.length==50;final ids=_rows.map((r)=>r['id']).toSet();_rows.addAll(page.where((r)=>!ids.contains(r['id'])));});
          }),child:Text(s('더 보기','Load more','ເບິ່ງເພີ່ມ'))),
        ])),
      ])),
    actions:[
      if(_throughAt!=null)FilledButton(key:const ValueKey('notifications-read-all'),onPressed:_busy || _completed || _unread==0 ? null : _readAll,
        child:Text(s('신규 알림 전체 확인 완료','Mark all new alerts as read','ຢືນຢັນອ່ານແຈ້ງເຕືອນໃໝ່ທັງໝົດ'))),
      TextButton(onPressed:_busy ? null : ()=>_act(()async{
        final data=await widget.loadPage(0);
        if(mounted && widget.isCurrentOwner())setState(()=>_setInitial(data));
      }),child:Text(s('새로고침','Refresh','ໂຫຼດໃໝ່'))),
      TextButton(onPressed:()=>Navigator.pop(context),child:Text(AppStrings.get(widget.language,'close'))),
    ],
  );
}
