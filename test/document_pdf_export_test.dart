import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/document_pdf_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Uint8List> documentImage(int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, 600, height.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 600, 24), Paint()..color = const Color(0xFFFF0000));
    canvas.drawRect(Rect.fromLTWH(0, height - 24.0, 600, 24), Paint()..color = const Color(0xFF0000FF));
    final picture = recorder.endRecording();
    final image = await picture.toImage(600, height);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    image.dispose(); picture.dispose();
    return bytes;
  }
  int pageCount(Uint8List bytes) => RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length;
  Future<void> save(String name, Uint8List bytes) async {
    final file = File('build/document-previews/$name.pdf');
    await file.parent.create(recursive: true); await file.writeAsBytes(bytes);
  }
  test('short, current-height and tall documents keep two copies on one A4 page', () async {
    for (final height in [350, 520, 1800]) {
      final image = await documentImage(height);
      final quotation = await DocumentPdfExport.quotation(image, sourceWidth: 600, sourceHeight: height.toDouble());
      final statement = await DocumentPdfExport.statementTwoUp(image, sourceWidth: 600, sourceHeight: height.toDouble());
      expect(pageCount(quotation), 1, reason: 'quotation height $height');
      expect(pageCount(statement), 1, reason: 'statement height $height');
      await save('a4_quotation_$height', quotation);
      await save('a4_statement_$height', statement);
    }
  });
  test('batch export adds one A4 page per statement regardless of source height', () async {
    final batch = StatementPdfBatchBuilder();
    for (final height in [350, 520, 1800]) {
      batch.addStatement(await documentImage(height), sourceWidth: 600, sourceHeight: height.toDouble());
    }
    final bytes = await batch.save();
    expect(pageCount(bytes), 3);
    await save('a4_batch', bytes);
  });
}
