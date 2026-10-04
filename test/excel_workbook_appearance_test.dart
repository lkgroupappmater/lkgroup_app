import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/services/excel_workbook_appearance.dart';

Uint8List workbook({bool colors = true}) {
  final archive = Archive();
  void add(String path, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }
  add('xl/workbook.xml', '<workbook xmlns:r="urn:relationships"><sheets><sheet name="고객 리스트" r:id="r1"/></sheets></workbook>');
  add('xl/_rels/workbook.xml.rels', '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>');
  if (colors) {
    add('xl/styles.xml', '<styleSheet><dxfs count="2"><dxf><fill><patternFill><fgColor rgb="FF123456"/></patternFill></fill></dxf><dxf><fill><patternFill><fgColor rgb="FFAABBCC"/></patternFill></fill></dxf></dxfs></styleSheet>');
    add('xl/worksheets/sheet1.xml', '<worksheet><conditionalFormatting><cfRule dxfId="0"><formula>SEARCH("지방배송",F2)</formula></cfRule><cfRule dxfId="1"><formula>SEARCH("시내배송(선결제)",F2)</formula></cfRule><cfRule dxfId="99"><formula>SEARCH("시내배송",F2)</formula></cfRule></conditionalFormatting></worksheet>');
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  test('imports category fill colors and ignores invalid differential style IDs', () {
    expect(ExcelWorkbookAppearance.read(workbook()), {'province': '123456', 'city_prepaid': 'AABBCC'});
  });
  test('workbooks without styles do not invent appearance overrides', () {
    expect(ExcelWorkbookAppearance.read(workbook(colors: false)), isEmpty);
  });
}
