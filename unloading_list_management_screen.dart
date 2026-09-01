import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    if (_route == null || _year == null || _voyage == null) {
      setState(() => _rows = const []);
      return;
    }
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
    final box = '${row['box_number'] ?? ''}';
    final m = RegExp(r'(\d+)').firstMatch(box);
    return m == null ? 999999999 : int.tryParse(m.group(1)!) ?? 999999999;
  }

  bool _needsAttention(Map<String, dynamic> row) {
    if (row['data_locked'] == true) return false;
    final name = '${row['consignee_name'] ?? ''}'.trim();
    final phone = '${row['consignee_phone'] ?? ''}'.trim();
    final receipt = '${row['receipt_number'] ?? ''}'.trim().toUpperCase();
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    bool placeholder(String value) {
      final v = value.trim().toLowerCase();
      if (v.isEmpty) return true;
      if (RegExp(r'[\?\*]{2,}').hasMatch(v)) return true;
      return v == 'xx' ||
          v.contains('수취인 불명') ||
          v.contains('수취인불명') ||
          v.contains('unknown');
    }

    return placeholder(name) ||
        placeholder(phone) ||
        digits.length < 8 ||
        receipt.endsWith('XX');
  }

  Future<Uint8List> _buildPdf() async {
    final fontData =
        await rootBundle.load('assets/fonts/NotoSansKR-Regular.otf');
    final font = pw.Font.ttf(fontData);
    const rowsPerColumn = 16;
    const columnGroups = 5;
    const perPage = rowsPerColumn * columnGroups;
    final document = pw.Document();
    final totalPages = (_rows.length / perPage).ceil().clamp(1, 999999);

    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final start = pageIndex * perPage;
      final pageRows = _rows.skip(start).take(perPage).toList(growable: false);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                '${_route ?? ''} · ${_year ?? ''}년 · ${_voyage ?? ''}항차 하역 Zone',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: font,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: List.generate(columnGroups, (group) {
                    final groupStart = group * rowsPerColumn;
                    return pw.Expanded(
                      child: pw.Padding(
                        padding: pw.EdgeInsets.only(
                          right: group == columnGroups - 1 ? 0 : 5,
                        ),
                        child: pw.Column(
                          children: List.generate(rowsPerColumn, (line) {
                            final idx = groupStart + line;
                            final cargo =
                                idx < pageRows.length ? pageRows[idx] : null;
                            final warning =
                                cargo != null && _needsAttention(cargo);
                            final bg =
                                warning ? PdfColors.yellow : PdfColors.white;
                            final box = cargo == null
                                ? ''
                                : '${cargo['box_number'] ?? ''}'.trim();
                            final zone = cargo == null
                                ? ''
                                : '${cargo['unloading_zone'] ?? ''}'.trim();

                            pw.Widget cell(String value, int flex) =>
                                pw.Expanded(
                                  flex: flex,
                                  child: pw.Container(
                                    height: 22,
                                    alignment: pw.Alignment.center,
                                    decoration: pw.BoxDecoration(
                                      color: bg,
                                      border: pw.Border.all(
                                        width: .45,
                                        color: PdfColors.black,
                                      ),
                                    ),
                                    child: pw.Text(
                                      value,
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
              pw.SizedBox(height: 4),
              pw.Text(
                '${pageIndex + 1} / $totalPages',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(font: font, fontSize: 7),
              ),
            ],
          ),
        ),
      );
    }
    return document.save();
  }

  Future<void> _savePdf() async {
    if (_rows.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _buildPdf();
      final prefix = RouteCatalog.filePrefixFor(_route ?? '');
      final fileName =
          '${prefix.isEmpty ? 'LK_GROUP' : prefix}_${_year}_${_voyage}_UNLOADING_ZONE.pdf';
      final path = await FilePicker.saveFile(
        dialogTitle: '하역 자료 PDF 저장',
        fileName: fileName,
        bytes: bytes,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (path != null) _message('하역 자료 PDF를 저장했습니다.');
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
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '관리자(직원) · 관리자(총괄) 전용',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
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
                    : (value) {
                        setState(() {
                          _route = value;
                          _year = null;
                          _voyage = null;
                          _rows = const [];
                        });
                      },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _year,
                decoration: const InputDecoration(
                  labelText: '년도',
                  border: OutlineInputBorder(),
                ),
                items: _years
                    .map((e) => DropdownMenuItem(value: e, child: Text('$e년')))
                    .toList(),
                onChanged: _route == null || _busy
                    ? null
                    : (value) {
                        setState(() {
                          _year = value;
                          _voyage = null;
                          _rows = const [];
                        });
                      },
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
                    : (value) {
                        setState(() {
                          _voyage = value;
                          _rows = const [];
                        });
                        if (value != null) _loadRows();
                      },
              ),
              const SizedBox(height: 14),
              if (_busy) const LinearProgressIndicator(),
              if (!_busy && _voyage != null)
                Text(
                  '화물 ${_rows.length}건 · 노란색 확인 필요 '
                  '${_rows.where(_needsAttention).length}건',
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _rows.isEmpty || _saving ? null : _savePdf,
                icon: _saving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('하역 자료 PDF 출력 / 저장'),
              ),
              const SizedBox(height: 10),
              const Text(
                '화물번호는 위에서 아래로 내려간 뒤 오른쪽 열로 이어집니다. '
                '수취인/연락처 불확실, ???/****, LKS XX 화물은 노란색이며 '
                '관리자가 확인 후 잠금한 화물은 노란색에서 제외됩니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}
