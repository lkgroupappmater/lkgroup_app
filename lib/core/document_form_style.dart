import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One visual system and content-sized layout for every route and export.
class DocumentFormStyle {
  DocumentFormStyle._();

  // Same palette and proportions as the web statement stylesheet.
  static const width = 1800.0;
  static const pagePadding = 18.0;
  static const contentWidth = width - pagePadding * 2;
  static const ink = Color(0xFF182433);
  static const line = Color(0xFF687A8C);
  static const paleBlue = Color(0xFFD9EAF7);
  static const actual = Color(0xFFFFE49A);
  static const volume = Color(0xFFCFE8BD);
  static const applied = Color(0xFFBFDDF1);
  static const total = Color(0xFFF2F5F8);
  static const totalLabel = Color(0xFFFFE86A);
  static const currencyUsd = Color(0xFFFCE48A);
  static const currencyKip = Color(0xFFFFC21A);
  static const currencyThb = Color(0xFF91D18B);
  static const currencyKrw = Color(0xFF23B6D8);
  static const tableTop = 266.0;
  static const headerHeight = 52.0;
  static const rowHeight = 38.0;
  static const emptyRowHeight = 32.0;
  static const totalsRowHeight = 36.0;
  static const textScale = 1.0;
  static const deliveryFontSize = 23.0;
  static const minimumSummaryHeight = 282.0;
  static const sectionGap = 8.0;
  static const remarkBoxWidth = (contentWidth - sectionGap * 2) * 1.25 / 2.87;
  static const deliveryBoxWidth = (contentWidth - sectionGap * 2) * .9 / 2.87;
  static const deliveryLeft = remarkBoxWidth + sectionGap;
  static const totalsLeft = deliveryLeft + deliveryBoxWidth + sectionGap;
  static const remarkWidth = remarkBoxWidth - 24;
  static const deliveryWidth = deliveryBoxWidth - 24;
  static const signatureWidth = contentWidth * .175;
  static const footerLeft = signatureWidth + sectionGap;
  static const footerBoxWidth = contentWidth - signatureWidth * 2 - sectionGap * 2;
  static const footerWidth = footerBoxWidth - 24;
  static const paymentHeight = 144.0;

  static List<double> get columns {
    // Web table's relative column widths (including its width normalization).
    const weights = [3.0, 7.0, 6.0, 4.5, 7.0, 7.0, 5.0, 5.0, 5.0, 8.0, 8.0, 10.0, 10.0, 12.0];
    final sum = weights.fold<double>(0, (a, b) => a + b);
    final result = <double>[0];
    for (final weight in weights) {
      result.add(result.last + contentWidth * weight / sum);
    }
    result[result.length - 1] = contentWidth;
    return result;
  }

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
      double lineHeight = 1.15, bool top = false}) {
    if (text.isEmpty || rect.isEmpty) return;
    final painter = textPainter(text, size, rect.width, bold: bold,
        align: center ? TextAlign.center : (right ? TextAlign.right : TextAlign.left),
        lineHeight: lineHeight);
    final scale = math.min(1.0, rect.height / painter.height);
    final drawnWidth = painter.width * scale;
    final x = center ? rect.left + (rect.width - drawnWidth) / 2
        : (right ? rect.right - drawnWidth : rect.left);
    canvas.save();
    canvas.translate(x, rect.top + (top ? 0 : (rect.height - painter.height * scale) / 2));
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
      : itemCount = math.max(0, itemCount),
        rowCount = math.max(10, itemCount + 1),
        summaryHeight = math.max(DocumentFormStyle.minimumSummaryHeight, math.max(
          DocumentFormStyle.textHeight(remark, remarkFontSize,
              DocumentFormStyle.remarkWidth, lineHeight: 1.45) + 68,
          DocumentFormStyle.textHeight(delivery, DocumentFormStyle.deliveryFontSize,
              DocumentFormStyle.deliveryWidth, bold: true, lineHeight: 1.35) + 68)),
        signHeight = math.max(148.0,
          DocumentFormStyle.textHeight(footer, footerFontSize,
              DocumentFormStyle.footerWidth, lineHeight: 1.25) + 24);

  final int itemCount;
  final int rowCount;
  final double summaryHeight;
  final double signHeight;
  double rowHeightAt(int index) => index < itemCount
      ? DocumentFormStyle.rowHeight : DocumentFormStyle.emptyRowHeight;
  double rowTop(int index) => DocumentFormStyle.tableTop
      + DocumentFormStyle.headerHeight
      + math.min(index, itemCount) * DocumentFormStyle.rowHeight
      + math.max(0, index - itemCount) * DocumentFormStyle.emptyRowHeight;
  double get tableTotalTop => rowTop(rowCount);
  double get summaryTop => tableTotalTop + DocumentFormStyle.totalsRowHeight + 12;
  double get paymentTop => summaryTop + summaryHeight + 12;
  double get signTop => paymentTop + DocumentFormStyle.paymentHeight + 12;
  double get rateNoteTop => signTop + signHeight + 8;
  double get height => DocumentFormStyle.pagePadding * 2 + rateNoteTop + 28;
}
