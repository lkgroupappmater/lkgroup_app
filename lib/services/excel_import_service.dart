import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../core/route_catalog.dart';
import 'shipment_service.dart';
import 'supabase_service.dart';
import '../config/supabase_config.dart';

class ExcelImportResult {
  const ExcelImportResult({
    required this.inserted,
    required this.skipped,
    required this.customerRules,
    this.message = '',
  });

  final int inserted;
  final int skipped;
  final int customerRules;
  final String message;
}

class ExcelImportService {
  ExcelImportService._();
  static final ExcelImportService instance = ExcelImportService._();

  Future<ExcelImportResult> pickAndImport() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (picked == null) {
      return const ExcelImportResult(
        inserted: 0,
        skipped: 0,
        customerRules: 0,
        message: '파일을 선택하지 않았습니다.',
      );
    }
    final bytes = await picked.readAsBytes();
    return importBytes(bytes, fileName: picked.name);
  }

  Future<ExcelImportResult> importBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final workbook = Excel.decodeBytes(bytes);
    final meta = _parseFileMeta(fileName);
    if (meta == null) {
      throw StateError(
        '파일명 형식을 확인해 주세요. 예: KR_LA_SEA_2026_V01_SHIPMENTS.xlsx',
      );
    }

    final routeKey = meta.$1;
    final routeLabel = RouteCatalog.labelForKey(routeKey);
    final year = meta.$2;
    final voyage = meta.$3;

    final rows = <Map<String, dynamic>>[];
    var skipped = 0;

    for (final entry in workbook.tables.entries) {
      final name = entry.key.trim();
      final sheet = entry.value;
      if (name != '물품 입고 내역') continue;
      final headerIndex = _findHeaderRow(sheet.rows);
      if (headerIndex < 0) continue;

      final headers = sheet.rows[headerIndex].map(_cellText).map(_normalise).toList();

      for (final row in sheet.rows.skip(headerIndex + 1)) {
        final map = <String, dynamic>{};
        for (var i = 0; i < headers.length && i < row.length; i++) {
          if (headers[i].isNotEmpty) map[headers[i]] = _cellText(row[i]).trim();
        }

        final box = '${map['box_number'] ?? ''}'.trim();
        if (box.isEmpty) {
          if (row.any((cell) => _cellText(cell).trim().isNotEmpty)) skipped++;
          continue;
        }

        // 미사용 예약행(S001 등)만 있는 빈 행은 업로드하지 않습니다.
        final hasBusinessData = [
          map['invoice_number'],
          map['sender_name'],
          map['consignee_name'],
          map['consignee_phone'],
          map['contents'],
          map['receipt_number'],
          map['weight_kg'],
        ].any((v) => '${v ?? ''}'.trim().isNotEmpty);
        if (!hasBusinessData) continue;

        rows.add({
          ...map,
          'route': routeLabel,
          'shipment_year': year,
          'voyage': voyage,
          'import_key': '$routeLabel|$year|$voyage|$box',
          if (routeKey == 'kr_la_air' && '${map['unloading_zone'] ?? ''}'.trim().isEmpty)
            'unloading_zone': '102',
        });
      }
    }

    _applyCalculatedZones(rows, routeKey: routeKey);

    final inserted = await ShipmentService.instance.upsertFromRows(rows);
    final customerRules =
        await _importCustomerDiscountRules(workbook, routeKey: routeKey);

    if (SupabaseConfig.isConfigured) {
      await _saveWorkbookTemplate(
        bytes: bytes,
        fileName: fileName,
        routeKey: routeKey,
        routeLabel: routeLabel,
        year: year,
        voyage: voyage,
      );
    }

    final noCargoSheet = rows.isEmpty &&
        !workbook.tables.keys.any((name) => name.trim() == '물품 입고 내역');

    return ExcelImportResult(
      inserted: inserted,
      skipped: skipped,
      customerRules: customerRules,
      message: noCargoSheet
          ? '원본 Excel 템플릿은 안전하게 저장했습니다. 현재 1차 자동 화물 동기화는 "물품 입고 내역" 시트가 있는 파일부터 지원합니다.'
          : '화물 데이터를 반영하고, 같은 항차의 원본 Excel 템플릿도 안전하게 저장했습니다.',
    );
  }

  Future<void> _saveWorkbookTemplate({
    required Uint8List bytes,
    required String fileName,
    required String routeKey,
    required String routeLabel,
    required int year,
    required String voyage,
  }) async {
    final path = '$routeKey/$year/V$voyage/$fileName';
    final storage = SupabaseService.client.storage.from('shipment-excel-templates');

    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        upsert: true,
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    );

    await SupabaseService.client.from('shipment_excel_templates').upsert({
      'route_key': routeKey,
      'route_label': routeLabel,
      'shipment_year': year,
      'voyage': voyage,
      'file_name': fileName,
      'storage_path': path,
      'uploaded_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'route_key,shipment_year,voyage');
  }

  void _applyCalculatedZones(
    List<Map<String, dynamic>> rows, {
    required String routeKey,
  }) {
    final receiptCounts = <String, int>{};
    for (final row in rows) {
      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      if (receipt.isEmpty) continue;
      final quantity = int.tryParse('${row['quantity'] ?? ''}') ?? 1;
      receiptCounts[receipt] = (receiptCounts[receipt] ?? 0) + (quantity < 1 ? 1 : quantity);
    }

    for (final row in rows) {
      final current = '${row['unloading_zone'] ?? ''}'.trim();
      final usableCurrent = current.isNotEmpty && !current.startsWith('=');
      if (usableCurrent) continue;

      if (routeKey == 'kr_la_air') {
        row['unloading_zone'] = '102';
        continue;
      }

      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      if (receipt.isEmpty) {
        row['unloading_zone'] = '';
        continue;
      }
      final count = receiptCounts[receipt] ?? 1;
      row['unloading_zone'] = count >= 20
          ? 'F'
          : count >= 10
              ? 'C'
              : count >= 5
                  ? 'B'
                  : 'A';
    }
  }

  Future<int> _importCustomerDiscountRules(
    Excel workbook, {
    required String routeKey,
  }) async {
    if (!SupabaseConfig.isConfigured) return 0;
    final sheet = workbook.tables['Row data'];
    if (sheet == null || sheet.rows.isEmpty) return 0;

    final rules = <Map<String, dynamic>>[];
    for (var r = 0; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      for (var c = 0; c < row.length; c++) {
        final value = _cellText(row[c]).trim();
        if (value != '이름') continue;

        // Excel의 할인 목록은 "이름 ... 할인율" 형태이므로 오른쪽 4칸 안에서 할인율 열을 찾습니다.
        var discountOffset = -1;
        for (var offset = 1; offset <= 4 && c + offset < row.length; offset++) {
          if (_cellText(row[c + offset]).trim() == '할인율') {
            discountOffset = offset;
            break;
          }
        }
        if (discountOffset < 0) continue;

        for (var rr = r + 1; rr < sheet.rows.length; rr++) {
          final dataRow = sheet.rows[rr];
          if (c >= dataRow.length) break;
          final name = _cellText(dataRow[c]).trim();
          if (name.isEmpty) break;
          final discountCell = c + discountOffset < dataRow.length
              ? _cellText(dataRow[c + discountOffset]).trim()
              : '';
          final discount = _toPercent(discountCell);
          if (discount == null) continue;
          rules.add({
            'customer_name': name,
            'route_key': routeKey,
            'discount_percent': discount,
            'active': true,
          });
        }
      }
    }

    if (rules.isEmpty) return 0;
    await SupabaseService.client
        .from('customer_rate_overrides')
        .upsert(rules, onConflict: 'customer_name,route_key');
    return rules.length;
  }

  static (String, int, String)? _parseFileMeta(String fileName) {
    final match = RegExp(
      r'^([A-Z]{2}_[A-Z]{2}_(?:SEA|AIR|AIR_EXP|LAND))_(\d{4})_V(\d{2})_SHIPMENTS\.XLSX$',
      caseSensitive: false,
    ).firstMatch(fileName.trim());
    if (match == null) return null;
    final prefix = match.group(1)!.toUpperCase();
    final key = RouteCatalog.keyFromFileName('${prefix}_');
    if (key == null) return null;
    return (key, int.parse(match.group(2)!), match.group(3)!);
  }

  static int _findHeaderRow(List<List<Data?>> rows) {
    for (var r = 0; r < rows.length && r < 20; r++) {
      final values = rows[r].map(_cellText).map(_normalise).toList();
      if (values.contains('box_number') &&
          (values.contains('consignee_name') || values.contains('invoice_number'))) {
        return r;
      }
    }
    return -1;
  }

  static String _cellText(dynamic cell) => cell?.value?.toString() ?? '';

  static double? _toPercent(String value) {
    final cleaned = value.replaceAll('%', '').trim();
    final parsed = double.tryParse(cleaned);
    if (parsed == null) return null;
    return value.contains('%') || parsed > 1 ? parsed / 100 : parsed;
  }

  static String _normalise(String value) {
    final key = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    const aliases = {
      'no.': 'box_number',
      'no': 'box_number',
      'box_no.': 'box_number',
      'box_no': 'box_number',
      '박스번호': 'box_number',
      '박스_번호': 'box_number',
      '송장_번호': 'invoice_number',
      '송장번호': 'invoice_number',
      '발신인': 'sender_name',
      '수신인': 'consignee_name',
      '수령인': 'consignee_name',
      '라오스_수령인': 'consignee_name',
      '전화번호': 'consignee_phone',
      '연락처': 'consignee_phone',
      '라오스_수령인_연락처': 'consignee_phone',
      '내용물': 'contents',
      '포장형태': 'package_type',
      '수량': 'quantity',
      '중량(kgs)': 'weight_kg',
      '중량(kg)': 'weight_kg',
      '중량': 'weight_kg',
      'l': 'length_cm',
      'w': 'width_cm',
      'h': 'height_cm',
      '영수_번호': 'receipt_number',
      '영수번호': 'receipt_number',
      '구획': 'unloading_zone',
      '비고': 'notes',
      'remark': 'notes',
      '접수일': 'received_at',
    };
    return aliases[key] ?? key;
  }
}
