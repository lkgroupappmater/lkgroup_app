import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/route_catalog.dart';
import 'statement_preview_dialog.dart';

class BatchStatementPdfDialog extends StatefulWidget {
  const BatchStatementPdfDialog({super.key, required this.selectedRows});

  final List<Map<String, dynamic>> selectedRows;

  @override
  State<BatchStatementPdfDialog> createState() => _BatchStatementPdfDialogState();
}

class _BatchStatementPdfDialogState extends State<BatchStatementPdfDialog> {
  bool _saving = false;

  int? _year(dynamic value) {
    if (value is num) return value.toInt();
    final m = RegExp(r'\d{4}').firstMatch('${value ?? ''}');
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  List<StatementRenderRequest> get _requests {
    final found = <String, StatementRenderRequest>{};
    for (final row in widget.selectedRows) {
      final route = '${row['route'] ?? ''}'.trim();
      final year = _year(row['shipment_year']);
      final voyage = '${row['voyage'] ?? ''}'.trim();
      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      if (route.isEmpty || year == null || voyage.isEmpty || receipt.isEmpty) continue;
      final key = '$route|$year|$voyage|$receipt';
      found.putIfAbsent(
        key,
        () => StatementRenderRequest(
          routeLabel: route,
          year: year,
          voyage: voyage,
          receiptNumber: receipt,
        ),
      );
    }
    return found.values.toList(growable: false);
  }

  Future<void> _save() async {
    final requests = _requests;
    if (requests.isEmpty) return;
    setState(() => _saving = true);
    try {
      final bytes = await StatementDocumentRenderer.renderBatchPdf(requests);
      final sameRoute = requests.every((e) => e.routeLabel == requests.first.routeLabel);
      final routePrefix = sameRoute ? RouteCatalog.filePrefixFor(requests.first.routeLabel) : '';
      final now = DateTime.now();
      final date = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final path = await FilePicker.saveFile(
        dialogTitle: '체크된 전체 명세서 출력용 PDF 저장',
        fileName: '${routePrefix.isEmpty ? 'LK_GROUP' : routePrefix}_STATEMENTS_${date}_${requests.length}.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (!mounted) return;
      if (path != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('총 ${requests.length}개의 명세서를 하나의 PDF로 저장했습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('전체 명세서 PDF 저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = _requests;
    return AlertDialog(
      title: const Text('체크된 명세서 출력용 PDF'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '총 ${requests.length}개의 명세서가 선택되었습니다.',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text('명세서 번호'),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: requests
                      .map((e) => Chip(label: Text(e.receiptNumber)))
                      .toList(growable: false),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '체크된 ${requests.length}개 명세서 전체를 하나의 출력용 PDF로 저장하시겠습니까?',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          onPressed: _saving || requests.isEmpty ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('전체 명세서 출력용 PDF 다운로드'),
        ),
      ],
    );
  }
}
