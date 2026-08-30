import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared PDF exporter for LK Group digital documents.
///
/// Statement/receipt:
/// - normal document: two identical copies on one A4 page (customer / office)
/// - tall document: one copy per A4 page to avoid unreadable squeezing
///
/// Quotation:
/// - one document per A4 page.
class DocumentPdfExport {
  DocumentPdfExport._();

  static Future<Uint8List> quotation(Uint8List pngBytes) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(pngBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(10),
        build: (_) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
    return pdf.save();
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
    final sourceRatio = sourceHeight / sourceWidth;
    final projectedHalfHeight = pageW * sourceRatio;

    // If one receipt naturally fits in half A4, print customer/office copies
    // top/bottom. Otherwise use two full A4 pages; never crush the receipt.
    if (projectedHalfHeight <= pageH * .485) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(8),
          build: (_) => pw.Column(
            children: [
              pw.Expanded(
                child: pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
              pw.Container(
                height: .6,
                color: PdfColors.grey600,
              ),
              pw.Expanded(
                child: pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.only(top: 3),
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
            margin: const pw.EdgeInsets.all(8),
            build: (_) => pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
        );
      }
    }

    return pdf.save();
  }
}
