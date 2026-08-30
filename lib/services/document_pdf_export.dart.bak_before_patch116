import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DocumentPdfExport {
  DocumentPdfExport._();

  static Future<Uint8List> quotation(
    Uint8List pngBytes, {
    required double sourceWidth,
    required double sourceHeight,
  }) async {
    return _twoUp(
      pngBytes,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  static Future<Uint8List> statementTwoUp(
    Uint8List pngBytes, {
    required double sourceWidth,
    required double sourceHeight,
  }) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(pngBytes);

    final pageW = PdfPageFormat.a4.width - 16;
    final pageH = PdfPageFormat.a4.height - 16;
    final projected = pageW * sourceHeight / sourceWidth;

    if (projected <= pageH * .485) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
          build: (_) => pw.Column(
            children: [
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
              pw.Container(
                height: 24,
                alignment: pw.Alignment.center,
                child: pw.Container(height: .6, color: PdfColors.grey600),
              ),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10),
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      for (var i = 0; i < 2; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
            build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      }
    }
    return pdf.save();
  }

  static Future<Uint8List> _twoUp(
    Uint8List pngBytes, {
    required double sourceWidth,
    required double sourceHeight,
  }) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    final pageW = PdfPageFormat.a4.width - 16;
    final pageH = PdfPageFormat.a4.height - 12;
    final projected = pageW * sourceHeight / sourceWidth;

    if (projected <= (pageH - 24) / 2) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
          build: (_) => pw.Column(
            children: [
              pw.Expanded(
                child: pw.Align(
                  alignment: pw.Alignment.topCenter,
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
              pw.Container(
                height: 24,
                alignment: pw.Alignment.center,
                child: pw.Container(height: .6, color: PdfColors.grey600),
              ),
              pw.Expanded(
                child: pw.Align(
                  alignment: pw.Alignment.topCenter,
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      for (var i = 0; i < 2; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
            build: (_) => pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
        );
      }
    }
    return pdf.save();
  }

}
