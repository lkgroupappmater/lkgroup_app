import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lkgroup_app/services/shipment_service.dart';
import 'package:lkgroup_app/services/excel_import_service.dart';

Uint8List workbook(List<List<String>> rows) {
  final archive = Archive();
  void add(String path,String text) { final bytes=utf8.encode(text); archive.addFile(ArchiveFile(path,bytes.length,bytes)); }
  add('xl/workbook.xml','<workbook><sheets><sheet name="물품 입고 내역" r:id="rId1"/></sheets></workbook>');
  add('xl/_rels/workbook.xml.rels','<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>');
  final all=[['No.','송장번호','수령인','전화번호','수량','중량'],...rows];
  add('xl/worksheets/sheet1.xml','<worksheet><sheetData>${all.asMap().entries.map((r)=>'<row r="${r.key+1}">${r.value.asMap().entries.map((c)=>'<c r="${String.fromCharCode(65+c.key)}${r.key+1}" t="inlineStr"><is><t>${c.value}</t></is></c>').join()}</row>').join()}</sheetData></worksheet>');
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls=<http.Request>[];
  var failApply=false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url:'https://company-search.invalid',publishableKey:'test-key',
      authOptions:const FlutterAuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request) async {
        calls.add(request);
        final preview=request.url.path.endsWith('admin_preview_shipment_excel_sync');
        return http.Response(jsonEncode(preview?{'preview_token':'reviewed','removed_rows':3}:failApply?{'message':'statement timeout','code':'57014'}:{'updated_rows':50,'removed_rows':3,'restored_rows':1}),
          !preview&&failApply?400:200,request:request,headers:{'content-type':'application/json'});
      }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() { calls.clear();failApply=false; });
  final rows=List.generate(50,(i)=><String,dynamic>{'route':'Test','shipment_year':2026,'voyage':'09','box_number':'S$i','invoice_number':'I$i','consignee_name':'Name','consignee_phone':'123','quantity':1});
  test('complete snapshot preview and apply share every row and token',() async {
    final summary=await ShipmentService.instance.synchronizeExcelRows(rows);
    expect(calls.length,2);
    final preview=jsonDecode(calls[0].body) as Map, apply=jsonDecode(calls[1].body) as Map;
    expect(calls[1].url.path,endsWith('admin_apply_shipment_excel_sync'));
    expect(apply['p_preview_token'],'reviewed');expect(apply['p_rows'],preview['p_rows']);expect((apply['p_rows'] as List).length,50);
    expect(summary.updatedRows,50);expect(summary.removedRows,3);expect(summary.restoredRows,1);
  });
  test('timeout does not fall back to partial chunks',() async {
    failApply=true;
    await expectLater(ShipmentService.instance.synchronizeExcelRows(rows),throwsA(isA<PostgrestException>()));
    expect(calls.length,2);
  });
  test('empty snapshots cannot call server',() async {
    await expectLater(ShipmentService.instance.synchronizeExcelRows([]),throwsStateError);expect(calls,isEmpty);
  });
  test('bad and duplicate workbook rows fail before database or rule writes',() async {
    for(final data in <List<List<String>>>[
      [['S1','I1','Name','123','1','5'],['s1','I2','Name','123','1','5']],
      [['','I1','Name','123','1','5']],
      [['S1','I1','Name','123','oops','5']],
      [],
    ]) {
      await expectLater(ExcelImportService.instance.importBytes(workbook(data),fileName:'KR_LA_SEA_2026_V09.xlsx'),throwsFormatException);
    }
    expect(calls,isEmpty);
  });
}
