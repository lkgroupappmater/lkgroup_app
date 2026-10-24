import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/cargo_number_input.dart';
import '../lib/core/shipment_customer_prefill.dart';

void main() {
  test('route prefixes retain split suffixes and never duplicate an existing prefix', () {
    for (final prefix in ['S','A','B','TL','LT','LV','VL','LC','CL','LCB','CBL']) {
      expect(CargoNumberInput.complete('270(02)',prefix),'${prefix}270(02)');
      expect(CargoNumberInput.complete('${prefix.toLowerCase()}270(02)',prefix),'${prefix}270(02)');
      expect(CargoNumberInput.complete('',prefix),'');
      final formatted=CargoNumberInput.formatter(prefix).formatEditUpdate(TextEditingValue.empty,TextEditingValue(text:'${prefix}270(02)',selection:TextSelection.collapsed(offset:prefix.length+7)));
      expect(formatted.text,'270(02)');
    }
  });
  testWidgets('customer defaults preserve manual edits, deletion and current voyage', (tester) async {
    final name=TextEditingController(text:'Customer'),phone=TextEditingController(text:'02012345678'),zone=TextEditingController(),notes=TextEditingController();
    var scope='Sea|2026|10';final pending=<Completer<Map<String,dynamic>>>[];
    final helper=ShipmentCustomerPrefill(name:name,phone:phone,zone:zone,notes:notes,scope:()=>scope,lookup:(n,p){final result=Completer<Map<String,dynamic>>();pending.add(result);return result.future;});
    helper.refresh();await tester.pump(const Duration(milliseconds:351));
    pending.removeAt(0).complete({'status':'matched','values':{'unloading_zone':'ST','notes':'지방배송'}});await tester.pump();
    expect(zone.text,'ST');expect(notes.text,'지방배송');
    notes.clear();zone.text='Z';helper.refresh();await tester.pump(const Duration(milliseconds:351));
    pending.removeAt(0).complete({'status':'matched','values':{'unloading_zone':'C','notes':'시내배송'}});await tester.pump();
    expect(zone.text,'Z');expect(notes.text,'');
    final work=helper.runNow();scope='Air|2026|20';helper.refresh();
    pending.removeAt(0).complete({'status':'matched','values':{'unloading_zone':'OLD','notes':'OLD'}});await work;
    expect(zone.text,'Z');expect(notes.text,'');
    helper.dispose();for(final c in [name,phone,zone,notes])c.dispose();
  });
}
