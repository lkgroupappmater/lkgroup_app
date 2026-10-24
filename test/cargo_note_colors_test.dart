import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/cargo_note_colors.dart';
import 'package:lkgroup_app/widgets/delivery_note_highlight.dart';

void main() {
  test('four workbook categories include legacy spelling without changing notes', () {
    const cases = {'지방배송':'province','지방 배송 (선결재)':'province_prepaid',
      '시내배송':'city','시내배소(선결재)':'city_prepaid','City delivery (prepaid)':'city_prepaid',
      '시내배송 / 통관 선불':'city','일반 고객':''};
    for (final e in cases.entries) {
      final row = {'notes': e.key}; expect(CargoNoteColors.kind(row), e.value);
      expect(row['notes'], e.key);
    }
    expect(CargoNoteColors.kind({'special_note_auto':'지방배송','notes':'시내배송'}), 'province');
    expect(CargoNoteColors.color({'notes':'일반 고객'}), isNull);
  });
  test('voyage palette overrides BASE only for valid changed entries', () {
    final colors = CargoNoteColors.palette({'city_prepaid':'D6B58C','province':'FFC000'}, {'province':'#123456','city':'not-a-color'});
    expect(colors['province'], '123456');expect(colors['city_prepaid'], 'D6B58C');expect(colors['city'], 'A9D18E');
    expect(CargoNoteColors.color({'notes':'시내배송(선결제)'}, colors), const Color(0xFFD6B58C));
  });
  testWidgets('palette update retains the note controller and selected text', (tester) async {
    final controller = TextEditingController(text:'지방배송(선결재) / 고객 메모');
    final pending = Completer<Map<String,String>>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DeliveryNoteHighlight.field(
      row: const {'route':'한국->라오스 해상','shipment_year':2026,'voyage':'10'},controller:controller,
      decoration: const InputDecoration(labelText:'비고'),loadColors: (_) => pending.future))));
    controller.selection = const TextSelection(baseOffset:0,extentOffset:4);
    pending.complete(CargoNoteColors.palette({'province_prepaid':'ABCDEF'}));await tester.pump();
    final field=tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.fillColor,const Color(0xFFABCDEF));expect(field.controller,same(controller));
    expect(controller.text,'지방배송(선결재) / 고객 메모');expect(controller.selection.extentOffset,4);
    await tester.pumpWidget(const SizedBox());controller.dispose();
  });
}
