import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _pageMargin = 7 * PdfPageFormat.mm;
const _cutGap = 6 * PdfPageFormat.mm;

pw.Widget _centerCutLine() => pw.Container(
      height: _cutGap,
      alignment: pw.Alignment.center,
      child: pw.Row(
        children: List<pw.Widget>.generate(
          48,
          (index) => pw.Expanded(
            child: pw.Container(
              height: .7,
              color: index.isEven ? PdfColors.grey600 : PdfColors.white,
            ),
          ),
        ),
      ),
    );

// Keep two complete copies on one A4 page even when a translated address,
// remark or additional cargo rows make the source image taller. Match the web
// print layout: 7 mm margins, 6 mm cut gap and 1 mm rounding allowance.
pw.Page _twoUpPage(pw.ImageProvider image) {
  final width = PdfPageFormat.a4.width - _pageMargin * 2;
  final height = PdfPageFormat.a4.height - _pageMargin * 2 - PdfPageFormat.mm;
  final copyHeight = (height - _cutGap) / 2;
  pw.Widget copy() => pw.SizedBox(
        width: width,
        height: copyHeight,
        child: pw.Image(image, width: width, height: copyHeight,
            fit: pw.BoxFit.contain),
      );
  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(_pageMargin),
    build: (_) => pw.Column(children: [copy(), _centerCutLine(), copy()]),
  );
}

class DocumentPdfExport {
  DocumentPdfExport._();

  static Future<Uint8List> quotation(
    Uint8List pngBytes, {
    required double sourceWidth,
    required double sourceHeight,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(_twoUpPage(pw.MemoryImage(pngBytes)));
    return pdf.save();
  }

  static Future<Uint8List> statementTwoUp(
    Uint8List imageBytes, {
    required double sourceWidth,
    required double sourceHeight,
  }) async {
    final batch = StatementPdfBatchBuilder();
    batch.addStatement(imageBytes,
        sourceWidth: sourceWidth, sourceHeight: sourceHeight);
    return batch.save();
  }

  static Future<Uint8List> batchStatements(List<Uint8List> imagePages) async {
    final batch = StatementPdfBatchBuilder();
    for (final bytes in imagePages) {
      batch.addStatement(bytes, sourceWidth: 1800, sourceHeight: 1120);
    }
    return batch.save();
  }
}

/// Assemble one A4 page per statement, with two fitted copies on each page.
class StatementPdfBatchBuilder {
  final pw.Document _pdf = pw.Document();

  void addStatement(
    Uint8List imageBytes, {
    required double sourceWidth,
    required double sourceHeight,
  }) {
    _pdf.addPage(_twoUpPage(pw.MemoryImage(imageBytes)));
  }

  Future<Uint8List> save() => _pdf.save();
}
