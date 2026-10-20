import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/app_language.dart';
import '../lib/widgets/notification_list_dialog.dart';

Map<String,dynamic> fixture()=>{'unread_count':2,'read_through_id':2,'read_through_at':'2026-10-20T10:00:00Z','rows':[
  {'id':1,'title':'First','message':'Approved','is_read':false,'created_at':'2026-10-20T09:00:00Z','request_details':{'receipt_number':'LKS 0045','changes':{'consignee_name':'Correct name','weight_kg':12},'admin_changes':{}}},
  {'id':2,'title':'Second','message':'Question','is_read':false,'created_at':'2026-10-20T09:01:00Z'}]};
Future<void> open(WidgetTester tester, Map<String,dynamic> data,{Future<Map<String,dynamic>> Function(int,String)? bulk}) async {
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(child:const Text('Open'),onPressed:()=>showDialog<void>(context:context,builder:(_)=>NotificationListDialog(
    language:AppLanguage.korean,initial:data,isCurrentOwner:()=>true,loadPage:(_)async=>data,
    onReadAll:bulk ?? (id,at)async=>{'unread_count':0},
    onOpen:(row)async{
      await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text('Detail ${row['id']}'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Close detail'))]));
    },
  )))))));
  await tester.tap(find.text('Open'));await tester.pumpAndSettle();
}
void main(){
 test('empty admin changes retain requested values and available old values',(){
   final row=(fixture()['rows'] as List).first as Map<String,dynamic>;
   expect(notificationDetails(row,AppLanguage.korean).join('\n'),contains('Correct name'));
   row['request_details']['admin_changes']={'weight_kg':14};row['request_details']['before_values']={'weight_kg':10};
   expect(notificationDetails(row,AppLanguage.korean).join('\n'),contains('10 → 14'));
 });
 testWidgets('list remains mounted across two separate detail dialogs',(tester)async{
   await open(tester,fixture());
   expect(find.textContaining('Correct name'),findsOneWidget);
   await tester.tap(find.byKey(const ValueKey('notification-1')));await tester.pumpAndSettle();
   expect(find.byType(NotificationListDialog,skipOffstage:false),findsOneWidget);expect(find.text('Detail 1'),findsOneWidget);
   await tester.tap(find.text('Close detail'));await tester.pumpAndSettle();
   await tester.tap(find.byKey(const ValueKey('notification-2')));await tester.pumpAndSettle();
   expect(find.text('Detail 2'),findsOneWidget);expect(tester.takeException(),isNull);
 });
 testWidgets('bulk review uses original snapshot and preserves a later unread count',(tester)async{
   final calls=<Object>[];
   await open(tester,fixture(),bulk:(id,at)async{calls.add([id,at]);return {'unread_count':1};});
   expect(calls,isEmpty);
   await tester.tap(find.byKey(const ValueKey('notifications-read-all')));await tester.pumpAndSettle();
   expect(calls,[[2,'2026-10-20T10:00:00Z']]);expect(find.text('알림 (1)'),findsOneWidget);
   expect(tester.widget<FilledButton>(find.byKey(const ValueKey('notifications-read-all'))).onPressed,isNull);
   expect(find.byType(NotificationListDialog),findsOneWidget);
 });
 testWidgets('failed bulk review stays unread and can retry on a narrow screen',(tester)async{
   tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
   addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
   await open(tester,fixture(),bulk:(id,at)async=>throw StateError('Offline'));
   await tester.tap(find.byKey(const ValueKey('notifications-read-all')));await tester.pumpAndSettle();
   expect(find.textContaining('Offline'),findsOneWidget);expect(find.text('알림 (2)'),findsOneWidget);
   expect(tester.widget<FilledButton>(find.byKey(const ValueKey('notifications-read-all'))).onPressed,isNotNull);
   expect(tester.takeException(),isNull);
 });
}
