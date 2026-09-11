import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One visual system and content-sized layout for every route and export.
class DocumentFormStyle {
  DocumentFormStyle._();

  static const width = 1800.0;
  static const ink = Color(0xFF20334D);
  static const line = Color(0xFFCCD6E2);
  static const paleBlue = Color(0xFFEAF1F8);
  static const actual = Color(0xFFFFF4DE);
  static const volume = Color(0xFFEAF4EC);
  static const applied = Color(0xFFE3EFFB);
  static const total = Color(0xFFF3F7FC);
  static const totalLabel = Color(0xFFD8E6F5);
  static const tableTop = 224.0;
  static const headerHeight = 56.0;
  static const rowHeight = 42.0;
  static const textScale = 1.15;
  static const deliveryFontSize = 24.0;
  static const minimumSummaryHeight = 232.0;
  static const remarkWidth = width * .70 * .58 - 20;
  static const deliveryWidth = width * .70 * .42 - 24;
  static const footerWidth = width * .48 - 36;

  static TextPainter textPainter(String text, double size, double width,
      {bool bold = false, TextAlign align = TextAlign.left,
      double lineHeight = 1.15}) {
    return TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        color: ink, fontFamily: 'NotoSansKR',
        fontFamilyFallback: const ['PhetsarathOT'], fontSize: size * textScale,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        height: lineHeight,
      )),
      textDirection: TextDirection.ltr, textAlign: align,
    )..layout(maxWidth: width);
  }

  static double textHeight(String text, double size, double width,
      {bool bold = false, double lineHeight = 1.15}) {
    final painter = textPainter(text, size, width,
        bold: bold, lineHeight: lineHeight);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// Fit bounded cells without discarding text. Notes use measured full height.
  static void drawText(Canvas canvas, String text, Rect rect, double size,
      {bool bold = false, bool center = false, bool right = false,
      double lineHeight = 1.15}) {
    if (text.isEmpty || rect.isEmpty) return;
    final painter = textPainter(text, size, rect.width, bold: bold,
        align: center ? TextAlign.center : (right ? TextAlign.right : TextAlign.left),
        lineHeight: lineHeight);
    final scale = math.min(1.0, rect.height / painter.height);
    final drawnWidth = painter.width * scale;
    final x = center ? rect.left + (rect.width - drawnWidth) / 2
        : (right ? rect.right - drawnWidth : rect.left);
    canvas.save();
    canvas.translate(x, rect.top + (rect.height - painter.height * scale) / 2);
    canvas.scale(scale);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
    painter.dispose();
  }
}

class DocumentFormLayout {
  DocumentFormLayout({required int itemCount, required String remark,
    required double remarkFontSize, required String footer,
    required double footerFontSize, String delivery = ''})
      : rowCount = math.max(10, itemCount + 1),
        summaryHeight = math.max(DocumentFormStyle.minimumSummaryHeight, math.max(
          DocumentFormStyle.textHeight(remark, remarkFontSize,
              DocumentFormStyle.remarkWidth, lineHeight: 1.2) + 60,
          DocumentFormStyle.textHeight(delivery, DocumentFormStyle.deliveryFontSize,
              DocumentFormStyle.deliveryWidth, bold: true, lineHeight: 1.16) + 62)),
        signHeight = math.max(112.0,
          DocumentFormStyle.textHeight(footer, footerFontSize,
              DocumentFormStyle.footerWidth, lineHeight: 1.2) + 24);

  final int rowCount;
  final double summaryHeight;
  final double signHeight;
  double get summaryTop => DocumentFormStyle.tableTop
      + DocumentFormStyle.headerHeight
      + (rowCount + 1) * DocumentFormStyle.rowHeight + 12;
  double get paymentTop => summaryTop + summaryHeight + 16;
  double get signTop => paymentTop + 150 + 16;
  double get height => signTop + signHeight + 16;
}

