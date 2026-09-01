import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../services/excel_bulk_management_service.dart';

class UnloadingListManagementScreen extends StatefulWidget {
  const UnloadingListManagementScreen({super.key});

  @override
  State<UnloadingListManagementScreen> createState() =>
      _UnloadingListManagementScreenState();
}

class _UnloadingListManagementScreenState
    extends State<UnloadingListManagementScreen> {
  List<ExcelBulkBatch> _batches = const [];
  List<Map<String, dynamic>> _rows = const [];

  String? _route;
  int? _year;
  String? _voyage;
  bool _busy = true;
  bool _saving = false;

  List<String> get _routes => _batches
      .map((e) => e.route)
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<int> get _years {
    final values = _batches
        .where((e) => _route == null || e.route == _route)
        .map((e) => e.year)
        .where((e) => e > 0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }

  List<String> get _voyages {
    final values = _batches
        .where((e) =>
            (_route == null || e.route == _route) &&
            (_year == null || e.year == _year))
        .map((e) => e.voyage)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await ExcelBulkManagementService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _message('항차 목록 조회 실패: $e');
    }
  }

  Future<void> _loadRows() async {
    if (_route == null || _year == null || _voyage == null) return;
    setState(() => _busy = true);
    try {
      final rows = await ExcelBulkManagementService.instance.listRows(
        route: _route!,
        year: _year!,
        voyage: _voyage!,
      );
      rows.sort((a, b) => _boxOrder(a).compareTo(_boxOrder(b)));
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      _message('하역 자료 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _boxOrder(Map<String, dynamic> row) {
    final m = RegExp(r'(\d+)')
        .firstMatch('${row['box_number'] ?? ''}');
    return m == null ? 999999999 : int.tryParse(m.group(1)!) ?? 999999999;
  }

  bool _hasAmbiguousMarker(String value) =>
      RegExp(r'[\?\*]{2,}').hasMatch(value);

  bool _needsAttention(Map<String, dynamic> row) {
    if (row['data_locked'] == true) return false;

    final name = '${row['consignee_name'] ?? ''}'.trim();
    final phone = '${row['consignee_phone'] ?? ''}'.trim();
    final receipt = '${row['receipt_number'] ?? ''}'.trim().toUpperCase();
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    final lowerName = name.toLowerCase();
    final lowerPhone = phone.toLowerCase();

    final missing = name.isEmpty ||
        phone.isEmpty ||
        digits.length < 8 ||
        receipt.endsWith('XX');

    final uncertain = _hasAmbiguousMarker(name) ||
        _hasAmbiguousMarker(phone) ||
        lowerName.contains('unknown') ||
        lowerName.contains('수취인 불명') ||
        lowerName.contains('수취인불명') ||
        lowerPhone.contains('unknown');

    return missing || uncertain;
  }

  Future<Uint8List> _buildPdf() async {
    // NotoSansKR OTF를 pdf.Font.ttf로 직접 파싱하는 과정에서
    // 일부 Android 환경에서 FormatException이 발생해,
    // 하역표는 숫자/영문 중심으로 built-in Helvetica를 사용합니다.
    final font = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();

    const rowsPerColumn = 16;
    const groups = 5;
    const perPage = rowsPerColumn * groups;

    final doc = pw.Document();
    final totalPages = (_rows.length / perPage).ceil();

    final routePrefix = RouteCatalog.filePrefixFor(_route ?? '');
    final titleRoute = routePrefix.isEmpty ? 'LK GROUP' : routePrefix;

    for (var page = 0; page < totalPages; page++) {
      final pageRows =
          _rows.skip(page * perPage).take(perPage).toList(growable: false);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(18),
          build: (_) => pw.Column(
            children: [
              pw.Text(
                '$titleRoute ${_year ?? ''} V${_voyage ?? ''} UNLOADING ZONE',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 13,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: List.generate(groups, (group) {
                    return pw.Expanded(
                      child: pw.Padding(
                        padding: pw.EdgeInsets.only(
                          right: group == groups - 1 ? 0 : 5,
                        ),
                        child: pw.Column(
                          children: List.generate(rowsPerColumn, (line) {
                            final index = group * rowsPerColumn + line;
                            final row =
                                index < pageRows.length ? pageRows[index] : null;
                            final warning =
                                row != null && _needsAttention(row);

                            final box = row == null
                                ? ''
                                : '${row['box_number'] ?? ''}'.trim();
                            final zone = row == null
                                ? ''
                                : '${row['unloading_zone'] ?? ''}'.trim();

                            pw.Widget cell(String text, int flex) =>
                                pw.Expanded(
                                  flex: flex,
                                  child: pw.Container(
                                    height: 22,
                                    alignment: pw.Alignment.center,
                                    decoration: pw.BoxDecoration(
                                      color: warning
                                          ? const PdfColor(1, 1, 0)
                                          : const PdfColor(1, 1, 1),
                                      border: pw.Border.all(
                                        width: .5,
                                        color: PdfColors.black,
                                      ),
                                    ),
                                    child: pw.Text(
                                      text,
                                      style: pw.TextStyle(
                                        font: font,
                                        fontSize: 8.5,
                                      ),
                                    ),
                                  ),
                                );

                            return pw.Row(
                              children: [
                                cell(box, 65),
                                cell(zone, 35),
                              ],
                            );
                          }),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              pw.Text(
                '${page + 1} / $totalPages',
                style: pw.TextStyle(font: font, fontSize: 7),
              ),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  Future<void> _savePdf() async {
    if (_rows.isEmpty || _saving) return;
    setState(() => _saving = true);

    try {
      final bytes = await _buildPdf();
      final prefix = RouteCatalog.filePrefixFor(_route ?? '');
      final fileName =
          '${prefix.isEmpty ? 'LK_GROUP' : prefix}_${_year}_V${_voyage}_UNLOADING_ZONE.pdf';

      final path = await FilePicker.saveFile(
        dialogTitle: '하역 자료 PDF 저장',
        fileName: fileName,
        bytes: bytes,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );

      if (path != null) _message('하역 자료 PDF 저장 완료');
    } catch (e) {
      _message('하역 자료 PDF 저장 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('하역 자료 관리'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _route,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '운송 경로',
                border: OutlineInputBorder(),
              ),
              items: _routes
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                        _route = v;
                        _year = null;
                        _voyage = null;
                        _rows = const [];
                      }),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _year,
              decoration: const InputDecoration(
                labelText: '년도',
                border: OutlineInputBorder(),
              ),
              items: _years
                  .map((e) =>
                      DropdownMenuItem(value: e, child: Text('$e년')))
                  .toList(),
              onChanged: _route == null || _busy
                  ? null
                  : (v) => setState(() {
                        _year = v;
                        _voyage = null;
                        _rows = const [];
                      }),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _voyage,
              decoration: const InputDecoration(
                labelText: '항차',
                border: OutlineInputBorder(),
              ),
              items: _voyages
                  .map((e) =>
                      DropdownMenuItem(value: e, child: Text('${e}항차')))
                  .toList(),
              onChanged: _year == null || _busy
                  ? null
                  : (v) {
                      setState(() {
                        _voyage = v;
                        _rows = const [];
                      });
                      if (v != null) _loadRows();
                    },
            ),
            const SizedBox(height: 14),
            if (_busy) const LinearProgressIndicator(),
            if (!_busy && _voyage != null)
              Text(
                '화물 ${_rows.length}건 · 노란색 확인 필요 ${_rows.where(_needsAttention).length}건',
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _rows.isEmpty || _saving ? null : _savePdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(
                _saving ? 'PDF 생성 중...' : '하역 자료 PDF 출력 / 저장',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '정상 이름이 포함되어 있어도 **, ***, ?? 같은 확인표시가 섞여 있으면 '
              '정상 영수번호는 유지하고 하역 자료에서만 노란색으로 표시합니다. '
              '관리자가 확인 후 잠금한 화물은 노란색에서 제외됩니다.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}
