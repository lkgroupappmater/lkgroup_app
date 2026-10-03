import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/measurement_input.dart';
import 'package:lkgroup_app/widgets/measurement_warning.dart';
void main(){
 test('blank is optional; every partial combination is rejected',(){
  expect(MeasurementInput.valid({}),true);
  for(var mask=1;mask<15;mask++){
   final values={for(var i=0;i<4;i++) MeasurementInput.fields[i]: mask&(1<<i)!=0?'12':''};
   expect(MeasurementInput.valid(values),false,reason:'mask $mask');
  }
  expect(MeasurementInput.valid({for(final k in MeasurementInput.fields) k:0}),true);
  for(final bad in ['-1','abc','NaN','Infinity']){
   expect(MeasurementInput.valid({for(final k in MeasurementInput.fields) k:1,'weight_kg':bad}),false);
  }
 });
 testWidgets('warning follows typing and clearing all four values',(tester)async{
  final c=List.generate(4,(_)=>TextEditingController());
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:MeasurementWarning(weight:c[0],length:c[1],width:c[2],height:c[3],language:AppLanguage.korean))));
  expect(find.text(MeasurementInput.message()),findsNothing);
  c[0].text='1';await tester.pump();expect(find.text(MeasurementInput.message()),findsOneWidget);
  for(final x in c)x.text='2';await tester.pump();expect(find.text(MeasurementInput.message()),findsNothing);
  for(final x in c)x.clear();await tester.pump();expect(find.text(MeasurementInput.message()),findsNothing);
  await tester.pumpWidget(const SizedBox());for(final x in c)x.dispose();
 });
}
