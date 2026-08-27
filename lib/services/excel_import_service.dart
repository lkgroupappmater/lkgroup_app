import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'shipment_service.dart';

class ExcelImportResult {
  const ExcelImportResult({required this.inserted, required this.skipped, this.message = ''});
  final int inserted;
  final int skipped;
  final String message;
}

class ExcelImportService {
  ExcelImportService._();
  static final ExcelImportService instance = ExcelImportService._();

  Future<ExcelImportResult> pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) {
      return const ExcelImportResult(inserted: 0, skipped: 0, message: '파일을 선택하지 않았습니다.');
    }
    return importBytes(picked.files.single.bytes!);
  }

  Future<ExcelImportResult> importBytes(Uint8List bytes) async {
    final workbook = Excel.decodeBytes(bytes);
    final rows = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final sheet in workbook.tables.values) {
      if (sheet.rows.isEmpty) continue;
      final headers = sheet.rows.first.map(_cellText).map(_normalise).toList();
      for (final row in sheet.rows.skip(1)) {
        if (row.every((cell) => _cellText(cell).trim().isEmpty)) continue;
        final map = <String, dynamic>{};
        for (var i = 0; i < headers.length && i < row.length; i++) {
          if (headers[i].isNotEmpty) map[headers[i]] = _cellText(row[i]).trim();
        }
        final invoice = '${map['invoice_number'] ?? map['invoice'] ?? map['shipment_no'] ?? ''}'.trim();
        if (invoice.isEmpty) { skipped++; continue; }
        rows.add(map);
      }
    }
    final inserted = await ShipmentService.instance.bulkCreateFromRows(rows);
    return ExcelImportResult(inserted: inserted, skipped: skipped, message: '엑셀 데이터 처리가 완료되었습니다.');
  }

  static String _cellText(dynamic cell) => cell?.value?.toString() ?? '';
  static String _normalise(String value) {
    final key = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    const aliases = {
      'box_no': 'box_number', '박스번호': 'box_number', '박스_번호': 'box_number',
      'invoice_no': 'invoice_number', '송장번호': 'invoice_number', '송장_번호': 'invoice_number',
      '수령인': 'consignee_name', '라오스_수령인': 'consignee_name', '전화번호': 'consignee_phone',
      '라오스_전화번호': 'consignee_phone', '입고날짜': 'received_at', '입고_날짜': 'received_at',
      '노선': 'route', '무게': 'weight_kg', '수량': 'quantity', '가로': 'width_cm', '세로': 'length_cm', '높이': 'height_cm',
    };
    return aliases[key] ?? key;
  }
}
