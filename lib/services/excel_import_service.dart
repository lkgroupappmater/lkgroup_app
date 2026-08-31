import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
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
    this.customerRulesWaitingForPhone = 0,
    this.message = '',
  });

  final int inserted;
  // Box No.가 없어서 화물로 처리하지 않은 요약/합계/안내 등의 비화물 행.
  final int skipped;
  // 이름+전화번호가 모두 있어 실제 적용 가능한 고객 할인규칙.
  final int customerRules;
  // 이름/할인율은 있으나 전화번호가 없어 안전상 적용 대기 중인 규칙.
  final int customerRulesWaitingForPhone;
  final String message;
}

class _DeliveryRowStyle {
  const _DeliveryRowStyle({
    this.greenColumns = const <int>{},
    this.yellowColumns = const <int>{},
  });

  final Set<int> greenColumns;
  final Set<int> yellowColumns;

  bool get isCity => greenColumns.isNotEmpty;

  bool preferredFor(int? companyColumn, int? destinationColumn) {
    if (yellowColumns.isEmpty) return false;
    if (companyColumn != null && yellowColumns.contains(companyColumn)) {
      return true;
    }
    if (destinationColumn != null &&
        yellowColumns.contains(destinationColumn)) {
      return true;
    }
    return companyColumn == null && destinationColumn == null;
  }
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
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.12, 'Excel 구조 확인 중');
    final workbook = _readRawWorkbook(bytes);
    onProgress?.call(0.25, '화물 행 분석 중');
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

    final cargoRows = workbook['물품 입고 내역'];
    if (cargoRows != null) {
      final headerIndex = _findHeaderRow(cargoRows);
      if (headerIndex >= 0) {
        final headers =
            cargoRows[headerIndex].map(_normalise).toList(growable: false);

        for (final row in cargoRows.skip(headerIndex + 1)) {
          final map = <String, dynamic>{};
          for (var i = 0; i < headers.length && i < row.length; i++) {
            if (headers[i].isNotEmpty) map[headers[i]] = row[i].trim();
          }

          final box = '${map['box_number'] ?? ''}'.trim();
          if (box.isEmpty) {
            if (row.any((cell) => cell.trim().isNotEmpty)) skipped++;
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

          // Excel 날짜 셀은 OOXML에서 2026-07-14 같은 문자열이 아니라
          // 46217 같은 serial number로 저장될 수 있습니다.
          // DB received_at은 timestamptz이므로 업로드 전에 ISO 날짜로 정규화합니다.
          final receivedAtRaw = '${map['received_at'] ?? ''}'.trim();
          if (receivedAtRaw.isNotEmpty) {
            map['received_at'] = _normaliseExcelDateValue(receivedAtRaw);
          }

          rows.add({
            ...map,
            'route': routeLabel,
            'shipment_year': year,
            'voyage': voyage,
            'import_key': '$routeLabel|$year|$voyage|$box',
            if (routeKey == 'kr_la_air' &&
                '${map['unloading_zone'] ?? ''}'.trim().isEmpty)
              'unloading_zone': '102',
          });
        }
      }
    }


    // 같은 Excel 안에 동일 import_key가 중복되어 있으면 PostgreSQL
    // ON CONFLICT DO UPDATE가 같은 row를 한 statement에서 두 번 갱신하려다
    // SQLSTATE 21000으로 실패할 수 있습니다.
    // 실제 DB 반영 전 import_key 기준으로 마지막 행 하나만 남깁니다.
    final uniqueRowsByImportKey = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final key = '${row['import_key'] ?? ''}'.trim();
      if (key.isEmpty) continue;
      uniqueRowsByImportKey[key] = row;
    }
    final uniqueRows = uniqueRowsByImportKey.values.toList(growable: false);

    // Patch167: current BASE Excel delivery table is the source of truth.
    // Import it before shipment upsert so normalize/finalize can see city/province
    // delivery + prepaid + company/address for this very upload.
    onProgress?.call(0.38, '시내·지방 배송표 DB 반영 중');
    await _importLocalDeliveryProfiles(bytes, workbook, routeKey: routeKey);

    onProgress?.call(0.45, '배송표 반영 완료 · 화물 DB 반영 중');
    final inserted = await ShipmentService.instance.upsertFromRows(uniqueRows);
    onProgress?.call(0.72, '화물 DB 반영 완료 · 고객 규칙 확인 중');
    final customerRuleResult =
        await _importCustomerDiscountRules(workbook, routeKey: routeKey);

    // One batch-scoped finalizer after all rows/rules are ready.
    // Do not silently finish an upload with missing delivery/receipt/zone data.
    if (SupabaseConfig.isConfigured) {
      onProgress?.call(0.82, '배송·구획·영수번호 최종 정리 중');
      await SupabaseService.client.rpc(
        'admin_finalize_excel_batch_rules',
        params: {
          'p_route': routeLabel,
          'p_year': year,
          'p_voyage': voyage,
        },
      );
    }

    onProgress?.call(0.86, '최종 규칙 반영 완료 · 원본 Excel 보관 중');

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

    onProgress?.call(0.96, '최종 정리 중');

    final noCargoSheet =
        rows.isEmpty && !workbook.keys.any((name) => name.trim() == '물품 입고 내역');

    return ExcelImportResult(
      inserted: inserted,
      skipped: skipped,
      customerRules: customerRuleResult.applied,
      customerRulesWaitingForPhone: customerRuleResult.waitingForPhone,
      message: noCargoSheet
          ? '원본 Excel 템플릿은 안전하게 저장했습니다. 현재 1차 자동 화물 동기화는 "물품 입고 내역" 시트가 있는 파일부터 지원합니다.'
          : '화물 데이터를 반영하고, 같은 항차의 원본 Excel 템플릿도 안전하게 저장했습니다.',
    );
  }

  Map<String, List<List<String>>> _readRawWorkbook(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final files = <String, List<int>>{};
    for (final file in archive.files) {
      if (file.isFile) {
        files[file.name] = List<int>.from(file.content as List<int>);
      }
    }

    final workbookBytes = files['xl/workbook.xml'];
    final relsBytes = files['xl/_rels/workbook.xml.rels'];
    if (workbookBytes == null || relsBytes == null) {
      throw const FormatException('Excel workbook 구조를 찾지 못했습니다.');
    }

    final workbookXml = utf8.decode(workbookBytes, allowMalformed: true);
    final relsXml = utf8.decode(relsBytes, allowMalformed: true);
    final sharedStrings = _readSharedStrings(files['xl/sharedStrings.xml']);

    final relationships = <String, String>{};
    final relPattern = RegExp(
      r'<Relationship\b[^>]*\bId="([^"]+)"[^>]*\bTarget="([^"]+)"[^>]*/?>',
      caseSensitive: false,
    );
    for (final match in relPattern.allMatches(relsXml)) {
      relationships[match.group(1)!] = match.group(2)!;
    }

    final result = <String, List<List<String>>>{};
    final sheetPattern = RegExp(
      r'<sheet\b[^>]*\bname="([^"]+)"[^>]*\br:id="([^"]+)"[^>]*/?>',
      caseSensitive: false,
    );

    for (final match in sheetPattern.allMatches(workbookXml)) {
      final name = _xmlDecode(match.group(1) ?? '').trim();
      final relId = match.group(2) ?? '';
      final rawTarget = relationships[relId];
      if (rawTarget == null || rawTarget.isEmpty) continue;

      var target = rawTarget.replaceAll(r'\', '/');
      while (target.startsWith('../')) {
        target = target.substring(3);
      }
      if (target.startsWith('/')) target = target.substring(1);
      final path = target.startsWith('xl/') ? target : 'xl/$target';
      final sheetBytes = files[path];
      if (sheetBytes == null) continue;

      result[name] = _readWorksheetRows(
        utf8.decode(sheetBytes, allowMalformed: true),
        sharedStrings,
      );
    }

    return result;
  }

  List<String> _readSharedStrings(List<int>? bytes) {
    if (bytes == null) return const [];
    final xml = utf8.decode(bytes, allowMalformed: true);
    final values = <String>[];

    final siPattern = RegExp(
      r'<si\b[^>]*>([\s\S]*?)</si>',
      caseSensitive: false,
    );
    final textPattern = RegExp(
      r'<t(?:\s[^>]*)?>([\s\S]*?)</t>',
      caseSensitive: false,
    );

    for (final si in siPattern.allMatches(xml)) {
      final body = si.group(1) ?? '';
      final text = textPattern
          .allMatches(body)
          .map((match) => _xmlDecode(match.group(1) ?? ''))
          .join();
      values.add(text);
    }
    return values;
  }

  List<List<String>> _readWorksheetRows(
    String xml,
    List<String> sharedStrings,
  ) {
    final rows = <List<String>>[];
    final rowPattern = RegExp(
      r'<row\b[^>]*>([\s\S]*?)</row>',
      caseSensitive: false,
    );
    // 중요: self-closing 빈 셀(<c .../>)이 다음 일반 셀(<c ...>...</c>)을
    // 삼키지 않도록 하나의 패턴으로 처리합니다.
    // 예: <c r="D6" .../><c r="E6" ...><v>...</v></c>
    // 기존 정규식은 D6부터 E6의 </c>까지 한 셀로 오인할 수 있었습니다.
    final cellPattern = RegExp(
      r'<c\b([^>]*?)(?:/>|>([\s\S]*?)</c>)',
      caseSensitive: false,
    );

    for (final rowMatch in rowPattern.allMatches(xml)) {
      final rowXml = rowMatch.group(1) ?? '';
      final values = <String>[];

      for (final cellMatch in cellPattern.allMatches(rowXml)) {
        final attrs = cellMatch.group(1) ?? '';
        final body = cellMatch.group(2) ?? '';
        final ref = RegExp(r'\br="([A-Z]+)\d+"', caseSensitive: false)
            .firstMatch(attrs)
            ?.group(1)
            ?.toUpperCase();
        if (ref == null) continue;

        final columnIndex = _columnIndex(ref);
        while (values.length <= columnIndex) {
          values.add('');
        }

        final type = RegExp(r'\bt="([^"]+)"', caseSensitive: false)
                .firstMatch(attrs)
                ?.group(1) ??
            '';
        String value;

        if (type == 'inlineStr') {
          final texts = RegExp(
            r'<t(?:\s[^>]*)?>([\s\S]*?)</t>',
            caseSensitive: false,
          ).allMatches(body);
          value =
              texts.map((m) => _xmlDecode(m.group(1) ?? '')).join();
        } else {
          final raw = RegExp(
                r'<v>([\s\S]*?)</v>',
                caseSensitive: false,
              ).firstMatch(body)?.group(1) ??
              '';
          if (type == 's') {
            final index = int.tryParse(raw.trim());
            value = index != null &&
                    index >= 0 &&
                    index < sharedStrings.length
                ? sharedStrings[index]
                : '';
          } else if (type == 'str') {
            value = _xmlDecode(raw);
          } else {
            value = raw.trim();
          }
        }

        values[columnIndex] = value;
      }
      rows.add(values);
    }

    return rows;
  }

  int _columnIndex(String letters) {
    var result = 0;
    for (final unit in letters.codeUnits) {
      result = result * 26 + (unit - 64);
    }
    return result - 1;
  }

  String _xmlDecode(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
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

  Future<int> _importLocalDeliveryProfiles(
    Uint8List bytes,
    Map<String, List<List<String>>> workbook, {
    required String routeKey,
  }) async {
    if (!SupabaseConfig.isConfigured) return 0;

    // Patch166: 새 BASE Excel은 지방배송/시내배송을 위·아래 별도 구간으로
    // 나누고 C열 Pay in advance를 명시합니다. 이제 색상/문구 추정보다
    // "구간 + Pay in advance"를 우선 source of truth로 사용합니다.
    const supportedRoutes = <String>{
      'kr_la_sea',
      'kr_la_air',
      'th_la_land',
    };
    if (!supportedRoutes.contains(routeKey)) return 0;

    String? sheetName;
    List<List<String>>? sheet;
    for (final entry in workbook.entries) {
      final normalized = entry.key
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\s,·ㆍ._-]+'), '');
      if (normalized == '시내지방배송' ||
          normalized == 'localdelivery' ||
          normalized == 'cityprovincedelivery') {
        sheetName = entry.key;
        sheet = entry.value;
        break;
      }
    }
    if (sheetName == null || sheet == null || sheet.isEmpty) return 0;

    final styles = _readLocalDeliveryStyles(bytes, sheetName);

    String keyOf(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s·ㆍ._/()\-]+'), '');

    bool hasPrepaidMarker(String value) {
      final key = keyOf(value);
      return key.contains('선결제') ||
          key.contains('선결재') ||
          key.contains('payinadvance') ||
          key.contains('prepaid');
    }

    Map<String, int> columnsFor(List<String> row) {
      final found = <String, int>{};
      for (var c = 0; c < row.length; c++) {
        final key = keyOf(row[c]);
        if (key.isEmpty) continue;
        if (!found.containsKey('source_no') &&
            (key == 'no' || key == '번호' || key == '순번' || key == '순서')) {
          found['source_no'] = c;
        } else if (!found.containsKey('pay_in_advance') &&
            (key == 'payinadvance' || key == '선결제' || key == '선결재')) {
          found['pay_in_advance'] = c;
        } else if (!found.containsKey('phone') &&
            (key.contains('전화') || key.contains('연락처') || key == 'tel' ||
                key == 'phone' || key == 'phonenumber' || key == 'mobile')) {
          found['phone'] = c;
        } else if (!found.containsKey('local_company') &&
            (key.contains('배송업체') || key.contains('배송회사') ||
                key.contains('운송회사') || key == 'localcompany' ||
                key == 'deliverycompany' || key == 'transportcompany')) {
          found['local_company'] = c;
        } else if (!found.containsKey('destination') &&
            (key.contains('목적지') || key.contains('배송지') || key.contains('주소') ||
                key == 'destinationaddress' || key == 'destination' || key == 'address')) {
          found['destination'] = c;
        } else if (!found.containsKey('paid_by') &&
            (key == 'paidby' || key == 'payment' || key.contains('결제') ||
                key.contains('지불'))) {
          found['paid_by'] = c;
        } else if (!found.containsKey('notes') &&
            (key == '비고' || key == 'remark' || key == 'remarks' ||
                key == 'note' || key == 'notes')) {
          found['notes'] = c;
        } else if (!found.containsKey('alternate_name') &&
            (key == 'receiver' || key.contains('수령인') || key.contains('수신인') ||
                key.contains('영문') || key.contains('englishname') ||
                key.contains('alternatename'))) {
          found['alternate_name'] = c;
        } else if (!found.containsKey('customer_name') &&
            (key == 'name' || key == '이름' || key == '성명' || key == '고객명' ||
                key == 'customername')) {
          found['customer_name'] = c;
        } else if (!found.containsKey('customer_company') &&
            (key == '회사명' || key == '상호' || key == '업체명' ||
                key == 'companyname' || key == 'customercompany')) {
          found['customer_company'] = c;
        }
      }
      return found;
    }

    String compactRow(List<String> row) => keyOf(row.join(' '));
    String? sectionType(List<String> row) {
      final key = compactRow(row);
      if (key.contains('지방배송고객list') || key.contains('지방배송고객목록') ||
          key.contains('provincedeliverycustomerlist')) {
        return 'province';
      }
      if (key.contains('시내배송고객list') || key.contains('시내배송고객목록') ||
          key.contains('citydeliverycustomerlist')) {
        return 'city';
      }
      return null;
    }

    final sections = <({int headerRow, int endRow, String? type, Map<String, int> columns})>[];
    String? pendingType;
    for (var r = 0; r < sheet.length; r++) {
      final marker = sectionType(sheet[r]);
      if (marker != null) {
        pendingType = marker;
        continue;
      }
      final columns = columnsFor(sheet[r]);
      final looksLikeHeader = columns.containsKey('source_no') &&
          columns.containsKey('customer_name') &&
          columns.containsKey('phone');
      if (!looksLikeHeader) continue;
      final startRow = r;
      var endRow = sheet.length;
      for (var rr = r + 1; rr < sheet.length; rr++) {
        if (sectionType(sheet[rr]) != null) {
          endRow = rr;
          break;
        }
      }
      sections.add((
        headerRow: startRow,
        endRow: endRow,
        type: pendingType,
        columns: columns,
      ));
      pendingType = null;
    }

    // 구형 BASE Excel 호환: 별도 지방/시내 구간명이 없던 파일도 기존처럼 읽습니다.
    if (sections.isEmpty) {
      final header = _findLocalDeliveryHeader(sheet);
      sections.add((
        headerRow: header.row,
        endRow: sheet.length,
        type: null,
        columns: header.columns,
      ));
    }

    String valueAt(List<String> row, int? index) {
      if (index == null || index < 0 || index >= row.length) return '';
      return row[index].trim();
    }

    final bySourceNo = <int, Map<String, dynamic>>{};
    for (final section in sections) {
      int? currentSourceNo;
      String currentCustomerName = '';
      String currentAlternateName = '';
      String currentCompanyName = '';
      String currentPhoneDisplay = '';
      bool currentPrepaid = false;

      int? col(String key) => section.columns[key];

      for (var rr = section.headerRow + 1; rr < section.endRow; rr++) {
        final row = sheet[rr];
        if (row.every((cell) => cell.trim().isEmpty)) continue;
        if (sectionType(row) != null) break;

        final sourceRaw = valueAt(row, col('source_no'));
        final parsedSource = int.tryParse(sourceRaw.replaceAll(RegExp(r'[^0-9]'), ''));
        final rowCustomer = valueAt(row, col('customer_name'));
        final rowAlternate = valueAt(row, col('alternate_name'));
        final rowCompany = valueAt(row, col('customer_company'));
        final rowPhone = valueAt(row, col('phone'));
        final payAdvance = valueAt(row, col('pay_in_advance'));

        // No.가 있는 행이 한 고객의 대표행이고, 다음 No. 전까지는 같은 고객의
        // 대체 배송업체/목적지 행으로 간주합니다.
        if (parsedSource != null) {
          currentSourceNo = parsedSource;
          currentCustomerName = rowCustomer;
          currentAlternateName = rowAlternate;
          currentCompanyName = rowCompany;
          currentPhoneDisplay = rowPhone;
          currentPrepaid = hasPrepaidMarker(payAdvance);
        } else if (currentSourceNo == null) {
          continue;
        }

        final sourceNo = currentSourceNo!;
        final customerName = rowCustomer.isNotEmpty ? rowCustomer : currentCustomerName;
        final alternateName = rowAlternate.isNotEmpty ? rowAlternate : currentAlternateName;
        final companyName = rowCompany.isNotEmpty ? rowCompany : currentCompanyName;
        final phoneDisplay = rowPhone.isNotEmpty ? rowPhone : currentPhoneDisplay;
        final normalizedPhone = _digits(phoneDisplay);
        final localCompany = valueAt(row, col('local_company'));
        final destination = valueAt(row, col('destination'));
        final rawPaidBy = valueAt(row, col('paid_by'));
        final notes = valueAt(row, col('notes'));

        final fallbackText = [payAdvance, destination, rawPaidBy, notes].join(' ');
        final prepaid = currentPrepaid || hasPrepaidMarker(fallbackText);
        // C열 Pay in advance가 있으면 그 값을 최우선으로 사용합니다.
        // 구형 자료 호환용으로 Destination/Paid by의 선결제/선결재/prepaid도 보조 판정.
        // 단, 일반적인 '선불' 단어만으로는 선결제로 승격하지 않습니다.
        final paidBy = prepaid ? '선결제' : rawPaidBy;

        final rowStyle = styles[rr] ?? const _DeliveryRowStyle();
        final rowText = row.join(' ').toLowerCase();
        final isCity = section.type == 'city' ||
            (section.type == null &&
                (rowStyle.isCity || rowText.contains('시내배송') ||
                    rowText.contains('시내 배송') || rowText.contains('city')));
        final preferred = rowStyle.preferredFor(
          col('local_company') ?? (row.length > 5 ? 5 : null),
          col('destination') ?? (row.length > 6 ? 6 : null),
        );

        if (customerName.isEmpty && alternateName.isEmpty && companyName.isEmpty) {
          continue;
        }

        final profile = <String, dynamic>{
          'route_key': routeKey,
          'source_no': sourceNo,
          'customer_name': customerName,
          'alternate_name': alternateName,
          'company_name': companyName,
          'phone': normalizedPhone,
          'phone_display': phoneDisplay,
          'delivery_type': isCity ? 'city' : 'province',
          'local_company': localCompany,
          'destination_address': destination,
          'paid_by': paidBy,
          'notes': notes,
          'preferred': preferred,
          'active': normalizedPhone.isNotEmpty &&
              (customerName.isNotEmpty || alternateName.isNotEmpty || companyName.isNotEmpty),
        };

        final existing = bySourceNo[sourceNo];
        // 같은 고객의 여러 후보행은 기존 정책대로 preferred(노란색)가 있으면 우선,
        // 없으면 대표행을 유지합니다. 고객 identity/Pay in advance는 대표행에서 승계됩니다.
        if (existing == null || (preferred && existing['preferred'] != true)) {
          bySourceNo[sourceNo] = profile;
        }
      }
    }

    if (bySourceNo.isEmpty) return 0;

    await SupabaseService.client.from('local_delivery_profiles').upsert(
          bySourceNo.values.toList(growable: false),
          onConflict: 'route_key,source_no',
        );

    // Patch167: do not run a global shipment refresh here.
    // importBytes() runs one batch-scoped finalizer after shipment upsert.
    return bySourceNo.length;
  }

  ({int row, Map<String, int> columns}) _findLocalDeliveryHeader(
    List<List<String>> sheet,
  ) {
    var bestRow = -1;
    var bestScore = -1;
    Map<String, int> best = const <String, int>{};

    String keyOf(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s·ㆍ._/()-]+'), '');

    for (var r = 0; r < sheet.length && r < 20; r++) {
      final found = <String, int>{};
      final row = sheet[r];
      for (var c = 0; c < row.length; c++) {
        final key = keyOf(row[c]);
        if (key.isEmpty) continue;

        if (!found.containsKey('source_no') &&
            (key == 'no' ||
                key == '번호' ||
                key == '순번' ||
                key == '순서')) {
          found['source_no'] = c;
          continue;
        }
        if (!found.containsKey('phone') &&
            (key.contains('전화') ||
                key.contains('연락처') ||
                key == 'phone' ||
                key == 'phonenumber' ||
                key == 'tel' ||
                key == 'mobile')) {
          found['phone'] = c;
          continue;
        }
        if (!found.containsKey('local_company') &&
            (key.contains('배송업체') ||
                key.contains('배송회사') ||
                key.contains('운송회사') ||
                key.contains('택배') ||
                key == 'localcompany' ||
                key == 'deliverycompany' ||
                key == 'transportcompany')) {
          found['local_company'] = c;
          continue;
        }
        if (!found.containsKey('destination') &&
            (key.contains('목적지') ||
                key.contains('배송지') ||
                key.contains('주소') ||
                key.contains('지점') ||
                key == 'destination' ||
                key == 'address')) {
          found['destination'] = c;
          continue;
        }
        if (!found.containsKey('paid_by') &&
            (key.contains('선불') ||
                key.contains('착불') ||
                key.contains('결제') ||
                key.contains('지불') ||
                key == 'paidby' ||
                key == 'payment')) {
          found['paid_by'] = c;
          continue;
        }
        if (!found.containsKey('notes') &&
            (key == '비고' ||
                key == 'remark' ||
                key == 'remarks' ||
                key == 'note' ||
                key == 'notes')) {
          found['notes'] = c;
          continue;
        }
        if (!found.containsKey('alternate_name') &&
            (key.contains('영문') ||
                key.contains('englishname') ||
                key.contains('alternatename') ||
                key.contains('라오스명') ||
                key.contains('laoname'))) {
          found['alternate_name'] = c;
          continue;
        }
        if (!found.containsKey('customer_company') &&
            !key.contains('배송') &&
            !key.contains('운송') &&
            !key.contains('택배') &&
            (key == '회사명' ||
                key == '상호' ||
                key == '업체명' ||
                key == 'companyname' ||
                key == 'customercompany')) {
          found['customer_company'] = c;
          continue;
        }
        if (!found.containsKey('customer_name') &&
            !key.contains('영문') &&
            !key.contains('english') &&
            !key.contains('라오') &&
            (key == '이름' ||
                key == '성명' ||
                key == '고객명' ||
                key == '수령인' ||
                key == '수신인' ||
                key == 'name' ||
                key == 'customername')) {
          found['customer_name'] = c;
        }
      }

      final score = found.length;
      if (score > bestScore) {
        bestRow = r;
        bestScore = score;
        best = found;
      }
    }

    if (bestRow >= 0 && bestScore >= 3) {
      return (row: bestRow, columns: best);
    }

    // Known BASE sheet fallback.
    return (
      row: 0,
      columns: <String, int>{
        'source_no': 0,
        'customer_name': 1,
        'alternate_name': 2,
        'phone': 3,
        'local_company': 4,
        'destination': 5,
        'paid_by': 6,
        'notes': 7,
      },
    );
  }

  Map<int, _DeliveryRowStyle> _readLocalDeliveryStyles(
    Uint8List bytes,
    String sheetName,
  ) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final files = <String, List<int>>{};
      for (final file in archive.files) {
        if (file.isFile) {
          files[file.name] = List<int>.from(file.content as List<int>);
        }
      }

      final workbookBytes = files['xl/workbook.xml'];
      final relsBytes = files['xl/_rels/workbook.xml.rels'];
      final stylesBytes = files['xl/styles.xml'];
      if (workbookBytes == null ||
          relsBytes == null ||
          stylesBytes == null) {
        return const <int, _DeliveryRowStyle>{};
      }

      final workbookXml = utf8.decode(workbookBytes, allowMalformed: true);
      final relsXml = utf8.decode(relsBytes, allowMalformed: true);
      final stylesXml = utf8.decode(stylesBytes, allowMalformed: true);

      final relationships = <String, String>{};
      final relPattern = RegExp(
        r'<Relationship\b[^>]*\bId="([^"]+)"[^>]*\bTarget="([^"]+)"[^>]*/?>',
        caseSensitive: false,
      );
      for (final match in relPattern.allMatches(relsXml)) {
        relationships[match.group(1)!] = match.group(2)!;
      }

      String? relId;
      final sheetPattern = RegExp(
        r'<sheet\b[^>]*\bname="([^"]+)"[^>]*\br:id="([^"]+)"[^>]*/?>',
        caseSensitive: false,
      );
      for (final match in sheetPattern.allMatches(workbookXml)) {
        if (_xmlDecode(match.group(1) ?? '') == sheetName) {
          relId = match.group(2);
          break;
        }
      }
      if (relId == null) return const <int, _DeliveryRowStyle>{};

      var target = relationships[relId] ?? '';
      target = target.replaceAll(r'\', '/');
      while (target.startsWith('../')) {
        target = target.substring(3);
      }
      if (target.startsWith('/')) target = target.substring(1);
      final sheetPath = target.startsWith('xl/') ? target : 'xl/$target';
      final sheetBytes = files[sheetPath];
      if (sheetBytes == null) return const <int, _DeliveryRowStyle>{};

      final fillColors = <String?>[];
      final fillsBody = RegExp(
        r'<fills\b[^>]*>([\s\S]*?)</fills>',
        caseSensitive: false,
      ).firstMatch(stylesXml)?.group(1);
      if (fillsBody != null) {
        final fillPattern = RegExp(
          r'<fill\b[^>]*>([\s\S]*?)</fill>',
          caseSensitive: false,
        );
        for (final fill in fillPattern.allMatches(fillsBody)) {
          final body = fill.group(1) ?? '';
          final rgb = RegExp(
            r'<fgColor\b[^>]*\brgb="([0-9A-Fa-f]{6,8})"',
            caseSensitive: false,
          ).firstMatch(body)?.group(1);
          fillColors.add(rgb?.toUpperCase());
        }
      }

      final styleFillIds = <int>[];
      final cellXfsBody = RegExp(
        r'<cellXfs\b[^>]*>([\s\S]*?)</cellXfs>',
        caseSensitive: false,
      ).firstMatch(stylesXml)?.group(1);
      if (cellXfsBody != null) {
        final xfPattern = RegExp(
          r'<xf\b([^>]*)/?>',
          caseSensitive: false,
        );
        for (final xf in xfPattern.allMatches(cellXfsBody)) {
          final attrs = xf.group(1) ?? '';
          final fillId = int.tryParse(
                RegExp(
                      r'\bfillId="(\d+)"',
                      caseSensitive: false,
                    ).firstMatch(attrs)?.group(1) ??
                    '',
              ) ??
              0;
          styleFillIds.add(fillId);
        }
      }

      final sheetXml = utf8.decode(sheetBytes, allowMalformed: true);
      final result = <int, _DeliveryRowStyle>{};
      final rowPattern = RegExp(
        r'<row\b[^>]*>([\s\S]*?)</row>',
        caseSensitive: false,
      );
      final cellPattern = RegExp(
        r'<c\b([^>]*?)(?:/>|>([\s\S]*?)</c>)',
        caseSensitive: false,
      );

      var rowOrdinal = 0;
      for (final rowMatch in rowPattern.allMatches(sheetXml)) {
        final green = <int>{};
        final yellow = <int>{};
        final rowXml = rowMatch.group(1) ?? '';

        for (final cellMatch in cellPattern.allMatches(rowXml)) {
          final attrs = cellMatch.group(1) ?? '';
          final styleIndex = int.tryParse(
            RegExp(
                  r'\bs="(\d+)"',
                  caseSensitive: false,
                ).firstMatch(attrs)?.group(1) ??
                '',
          );
          if (styleIndex == null ||
              styleIndex < 0 ||
              styleIndex >= styleFillIds.length) {
            continue;
          }

          final fillId = styleFillIds[styleIndex];
          if (fillId < 0 || fillId >= fillColors.length) continue;
          final rgb = fillColors[fillId];
          if (rgb == null || rgb.isEmpty) continue;

          final ref = RegExp(
            r'\br="([A-Z]+)\d+"',
            caseSensitive: false,
          ).firstMatch(attrs)?.group(1)?.toUpperCase();
          if (ref == null) continue;
          final column = _columnIndex(ref);
          final rgb6 = rgb.length >= 6
              ? rgb.substring(rgb.length - 6).toUpperCase()
              : rgb.toUpperCase();

          if (rgb6 == '92D050') green.add(column);
          if (rgb6 == 'FFFF00') yellow.add(column);
        }

        if (green.isNotEmpty || yellow.isNotEmpty) {
          result[rowOrdinal] = _DeliveryRowStyle(
            greenColumns: Set<int>.unmodifiable(green),
            yellowColumns: Set<int>.unmodifiable(yellow),
          );
        }
        rowOrdinal++;
      }

      return result;
    } catch (_) {
      // Style parsing failure must never block cargo import.
      return const <int, _DeliveryRowStyle>{};
    }
  }

  Future<({int applied, int waitingForPhone})> _importCustomerDiscountRules(
    Map<String, List<List<String>>> workbook, {
    required String routeKey,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      return (applied: 0, waitingForPhone: 0);
    }
    final sheet = workbook['Row data'];
    if (sheet == null || sheet.isEmpty) {
      return (applied: 0, waitingForPhone: 0);
    }

    final rules = <Map<String, dynamic>>[];
    var applied = 0;
    var waitingForPhone = 0;

    for (var r = 0; r < sheet.length; r++) {
      final row = sheet[r];
      for (var c = 0; c < row.length; c++) {
        final value = row[c].trim();
        if (!_isCustomerNameHeader(value)) continue;

        // 각 할인 목록은 "이름 ... 할인율" 구조입니다.
        // 전화번호/연락처 열은 차후 추가되더라도 같은 목록 안에서 자동 인식합니다.
        var discountOffset = -1;
        var phoneOffset = -1;
        for (var offset = 1; offset <= 6 && c + offset < row.length; offset++) {
          final header = row[c + offset].trim();
          if (discountOffset < 0 && _isDiscountHeader(header)) {
            discountOffset = offset;
          }
          if (phoneOffset < 0 && _isPhoneHeader(header)) {
            phoneOffset = offset;
          }
        }
        if (discountOffset < 0) continue;

        for (var rr = r + 1; rr < sheet.length; rr++) {
          final dataRow = sheet[rr];
          if (c >= dataRow.length) break;

          final name = dataRow[c].trim();
          if (name.isEmpty) break;

          final discountCell = c + discountOffset < dataRow.length
              ? dataRow[c + discountOffset].trim()
              : '';
          final discount = _toPercent(discountCell);
          if (discount == null) continue;

          final phone = phoneOffset >= 0 && c + phoneOffset < dataRow.length
              ? dataRow[c + phoneOffset].trim()
              : '';
          final normalizedPhone = _digits(phone);
          final ready = normalizedPhone.isNotEmpty;

          rules.add({
            'customer_name': name,
            'phone': normalizedPhone,
            'route_key': routeKey,
            'discount_percent': discount,
            // 동명이인/오적용 방지: 전화번호가 없는 규칙은 저장하되 적용하지 않습니다.
            'active': ready,
          });

          if (ready) {
            applied++;
          } else {
            waitingForPhone++;
          }
        }
      }
    }

    if (rules.isEmpty) {
      return (applied: 0, waitingForPhone: 0);
    }

    // Row data 안에서 같은 고객이 여러 할인 목록에 반복 등장할 수 있습니다.
    // 같은 customer_name + phone + route_key를 한 upsert statement에
    // 두 번 넣지 않도록 마지막 항목 하나만 남깁니다.
    final uniqueRules = <String, Map<String, dynamic>>{};
    for (final rule in rules) {
      final key =
          '${rule['customer_name'] ?? ''}|${rule['phone'] ?? ''}|${rule['route_key'] ?? ''}';
      uniqueRules[key] = rule;
    }

    await SupabaseService.client
        .from('customer_rate_overrides')
        .upsert(
          uniqueRules.values.toList(growable: false),
          onConflict: 'customer_name,phone,route_key',
        );

    return (applied: applied, waitingForPhone: waitingForPhone);
  }

  static String _normaliseExcelDateValue(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';

    // 이미 ISO/일반 날짜 문자열이면 그대로 둡니다.
    if (DateTime.tryParse(text) != null) return text;

    // Excel 1900 date system serial.
    // 25569 == 1970-01-01. 소수부가 있으면 시간까지 보존합니다.
    final serial = double.tryParse(text);
    if (serial != null && serial >= 30000 && serial <= 70000) {
      final milliseconds =
          ((serial - 25569) * Duration.millisecondsPerDay).round();
      final date = DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      );
      return date.toIso8601String();
    }

    // 날짜로 해석할 수 없는 값은 그대로 반환하여 기존 동작을 보존합니다.
    return text;
  }
  static bool _isCustomerNameHeader(String value) {
    final key = value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return key == '이름' ||
        key == '성명' ||
        key == '고객명' ||
        key == '수령인' ||
        key == 'name' ||
        key == 'customername';
  }

  static bool _isDiscountHeader(String value) {
    final key = value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return key == '할인율' ||
        key == '할인' ||
        key == 'discountrate' ||
        key == 'discount';
  }

  static bool _isPhoneHeader(String value) {
    final key = value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return key == '전화번호' ||
        key == '연락처' ||
        key == '휴대폰' ||
        key == '휴대전화' ||
        key == 'phone' ||
        key == 'phonenumber' ||
        key == 'tel' ||
        key == 'mobile';
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

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

  static int _findHeaderRow(List<List<String>> rows) {
    for (var r = 0; r < rows.length && r < 20; r++) {
      final values = rows[r].map(_normalise).toList();
      if (values.contains('box_number') &&
          (values.contains('consignee_name') ||
              values.contains('invoice_number'))) {
        return r;
      }
    }
    return -1;
  }

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
      '특이사항': 'sender_name',
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





