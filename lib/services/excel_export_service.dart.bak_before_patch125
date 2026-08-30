import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../config/supabase_config.dart';
import '../core/route_catalog.dart';
import 'supabase_service.dart';

class ExcelExportBatch {
  const ExcelExportBatch({
    required this.routeKey,
    required this.routeLabel,
    required this.year,
    required this.voyage,
    this.hasVoyageTemplate = false,
    this.hasBaseTemplate = false,
  });

  final String routeKey;
  final String routeLabel;
  final int year;
  final String voyage;
  final bool hasVoyageTemplate;
  final bool hasBaseTemplate;

  String get displayLabel => '$routeLabel · $year · V$voyage';

  String get templateLabel {
    if (hasVoyageTemplate) return '항차별 변경 폼';
    if (hasBaseTemplate) return '기본 폼';
    return '기본 폼 없음';
  }
}

class ExcelExportResult {
  const ExcelExportResult({
    required this.saved,
    required this.fileName,
    this.savedLocation = '',
    this.message = '',
  });

  final bool saved;
  final String fileName;
  final String savedLocation;
  final String message;
}

class ExcelExportService {
  ExcelExportService._();
  static final ExcelExportService instance = ExcelExportService._();

  Future<List<ExcelExportBatch>> listBatches() async {
    if (!SupabaseConfig.isConfigured) return const [];

    final shipmentRows = await SupabaseService.client
        .from('shipments')
        .select('route,shipment_year,voyage')
        .not('shipment_year', 'is', null)
        .neq('voyage', '')
        .order('shipment_year', ascending: false);

    final voyageTemplates = await SupabaseService.client
        .from('shipment_excel_templates')
        .select('route_key,shipment_year,voyage');

    final baseTemplates = await SupabaseService.client
        .from('shipment_excel_base_templates')
        .select('route_key')
        .eq('active', true);

    final voyageKeys = <String>{
      for (final raw in voyageTemplates)
        '${raw['route_key']}|${raw['shipment_year']}|${raw['voyage']}',
    };
    final baseKeys = <String>{
      for (final raw in baseTemplates) '${raw['route_key']}',
    };

    final dedup = <String, ExcelExportBatch>{};
    for (final raw in shipmentRows) {
      final routeLabel = '${raw['route'] ?? ''}'.trim();
      final year = (raw['shipment_year'] as num?)?.toInt();
      final voyage = '${raw['voyage'] ?? ''}'.trim();
      if (routeLabel.isEmpty || year == null || voyage.isEmpty) continue;

      final routeKey = RouteCatalog.keyFor(routeLabel);
      final key = '$routeKey|$year|$voyage';
      dedup[key] = ExcelExportBatch(
        routeKey: routeKey,
        routeLabel: routeLabel,
        year: year,
        voyage: voyage,
        hasVoyageTemplate: voyageKeys.contains(key),
        hasBaseTemplate: baseKeys.contains(routeKey),
      );
    }

    final result = dedup.values.toList();
    result.sort((a, b) {
      final yearCompare = b.year.compareTo(a.year);
      if (yearCompare != 0) return yearCompare;
      final routeCompare = a.routeLabel.compareTo(b.routeLabel);
      if (routeCompare != 0) return routeCompare;
      return b.voyage.compareTo(a.voyage);
    });
    return result;
  }

  Future<ExcelExportResult> exportAndSave(ExcelExportBatch batch) async {
    if (!SupabaseConfig.isConfigured) {
      return const ExcelExportResult(
        saved: false,
        fileName: '',
        message: 'Supabase 설정을 확인해 주세요.',
      );
    }
    if (!batch.hasVoyageTemplate && !batch.hasBaseTemplate) {
      throw StateError(
        '${batch.routeLabel} 기본 Excel 폼이 DB에 등록되어 있지 않습니다.',
      );
    }

    final response = await SupabaseService.client.functions.invoke(
      'export-shipment-excel',
      body: {
        'route_key': batch.routeKey,
        'shipment_year': batch.year,
        'voyage': batch.voyage,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      String detail = '${response.data}';
      try {
        if (response.data is Map && (response.data as Map)['error'] != null) {
          detail = '${(response.data as Map)['error']}';
        }
      } catch (_) {}
      throw StateError('Excel 생성 실패 (${response.status}): $detail');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final exportPath = '${data['storage_path'] ?? ''}';
    final fileName = '${data['file_name'] ?? ''}';
    if (exportPath.isEmpty || fileName.isEmpty) {
      throw StateError('생성된 Excel 정보를 받지 못했습니다.');
    }

    final Uint8List bytes = await SupabaseService.client.storage
        .from('shipment-excel-exports')
        .download(exportPath);

    final saveUri = await FilePicker.saveFile(
      dialogTitle: 'Excel 저장 위치 선택',
      fileName: fileName,
      bytes: bytes,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );

    if (saveUri == null) {
      return ExcelExportResult(
        saved: false,
        fileName: fileName,
        message: '휴대폰 파일 저장을 취소했습니다.',
      );
    }

    return ExcelExportResult(
      saved: true,
      fileName: fileName,
      savedLocation: saveUri.toString(),
      message: '선택한 위치에 Excel 파일을 저장했습니다.',
    );
  }
}
