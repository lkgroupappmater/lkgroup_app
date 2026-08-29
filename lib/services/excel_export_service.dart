import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../config/supabase_config.dart';
import 'supabase_service.dart';

class ExcelTemplateBatch {
  const ExcelTemplateBatch({
    required this.routeKey,
    required this.routeLabel,
    required this.year,
    required this.voyage,
    required this.fileName,
    required this.uploadedAt,
  });

  final String routeKey;
  final String routeLabel;
  final int year;
  final String voyage;
  final String fileName;
  final DateTime? uploadedAt;

  String get displayLabel =>
      '$routeLabel · $year · V$voyage · $fileName';

  factory ExcelTemplateBatch.fromJson(Map<String, dynamic> json) {
    return ExcelTemplateBatch(
      routeKey: '${json['route_key'] ?? ''}',
      routeLabel: '${json['route_label'] ?? ''}',
      year: (json['shipment_year'] as num?)?.toInt() ?? 0,
      voyage: '${json['voyage'] ?? ''}',
      fileName: '${json['file_name'] ?? ''}',
      uploadedAt: DateTime.tryParse('${json['uploaded_at'] ?? ''}'),
    );
  }
}

class ExcelExportResult {
  const ExcelExportResult({
    required this.saved,
    required this.fileName,
    this.message = '',
  });

  final bool saved;
  final String fileName;
  final String message;
}

class ExcelExportService {
  ExcelExportService._();
  static final ExcelExportService instance = ExcelExportService._();

  Future<List<ExcelTemplateBatch>> listTemplates() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client
        .from('shipment_excel_templates')
        .select(
          'route_key,route_label,shipment_year,voyage,file_name,uploaded_at',
        )
        .order('shipment_year', ascending: false)
        .order('voyage', ascending: false);

    return List<Map<String, dynamic>>.from(rows)
        .map(ExcelTemplateBatch.fromJson)
        .toList(growable: false);
  }

  Future<ExcelExportResult> exportAndSave(ExcelTemplateBatch batch) async {
    if (!SupabaseConfig.isConfigured) {
      return const ExcelExportResult(
        saved: false,
        fileName: '',
        message: 'Supabase 설정을 확인해 주세요.',
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
      throw StateError('Excel 생성 실패 (${response.status}): ${response.data}');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final exportPath = '${data['storage_path'] ?? ''}';
    final fileName = '${data['file_name'] ?? batch.fileName}';
    if (exportPath.isEmpty) {
      throw StateError('생성된 Excel 저장 위치를 받지 못했습니다.');
    }

    final Uint8List bytes = await SupabaseService.client.storage
        .from('shipment-excel-exports')
        .download(exportPath);

    final saved = await FilePicker.saveFile(
      dialogTitle: '최신 화물 Excel 저장',
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );

    return ExcelExportResult(
      saved: saved != null,
      fileName: fileName,
      message: saved == null
          ? '저장을 취소했습니다.'
          : '현재 DB 자료를 원본 Excel 템플릿에 반영하여 저장했습니다.',
    );
  }
}
