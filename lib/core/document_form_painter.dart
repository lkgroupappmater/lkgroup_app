import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'document_form_style.dart';

/// Shared printed furniture; callers supply their existing calculated amounts.
/// Used by quotations, single statements and batch statement exports.
class DocumentFormPainter {
  DocumentFormPainter._();

  static void box(Canvas c, Rect r, Color fill) {
    c.drawRect(r, Paint()..color = fill);
    c.drawRect(r, Paint()..color = DocumentFormStyle.line
      ..style = PaintingStyle.stroke..strokeWidth = 1.4);
  }

  static void image(Canvas c, ui.Image image, Rect r) {
    paintImage(canvas: c, rect: r, image: image, fit: BoxFit.contain,
      filterQuality: FilterQuality.high);
  }

  static void header(Canvas c, {required ui.Image logo, required String title,
    required String zone, required String customer, required String phone,
    required String lastLabel, required String lastValue}) {
    const w = DocumentFormStyle.contentWidth;
    image(c, logo, const Rect.fromLTWH(20, 6, 176, 94));
    DocumentFormStyle.drawText(c, title,
      const Rect.fromLTWH(212, 0, w - 490, 108), 44,
      bold: true, center: true);
    final zoneBox = Rect.fromLTWH(w - 262, 6, 262, 100);
    box(c, zoneBox, DocumentFormStyle.paleBlue);
    DocumentFormStyle.drawText(c, '구획(Zone)',
      Rect.fromLTWH(zoneBox.left + 8, 18, zoneBox.width - 16, 30), 22, center: true);
    DocumentFormStyle.drawText(c, zone.isEmpty ? '-' : zone,
      Rect.fromLTWH(zoneBox.left + 8, 50, zoneBox.width - 16, 44), 32,
      center: true, bold: true);

    const leftValues = [
      ('회사명', '엘케이(LK)무역'),
      ('회사주소', '비엔티엔시, 씨싿따낙구, 싸판텅 느아 09, 11번 골목, 엘케이(LK) 빌딩, 1층 LK Trading'),
      ('전화번호', '+856 20 9112 6780'),
    ];
    final rightValues = [('고객명/회사명', customer), ('연락처', phone), (lastLabel, lastValue)];
    // The taller address row keeps the same font as the other party fields.
    const heights = [42.0, 62.0, 42.0];
    var top = 120.0;
    for (var i = 0; i < 3; i++) {
      for (var side = 0; side < 2; side++) {
        final pair = side == 0 ? leftValues[i] : rightValues[i];
        final r = Rect.fromLTWH(side * w / 2, top, w / 2, heights[i]);
        box(c, r, const Color(0xFFF1F7FC));
        final label = Rect.fromLTWH(r.left, r.top, 176, r.height);
        box(c, label, const Color(0xFFF1F7FC));
        DocumentFormStyle.drawText(c, pair.$1, label.deflate(6), 20,
          center: true, bold: true, lineHeight: 1.25);
        DocumentFormStyle.drawText(c, pair.$2.isEmpty ? '-' : pair.$2,
          Rect.fromLTRB(label.right + 8, r.top + 4, r.right - 8, r.bottom - 4), 20,
          center: true, bold: true, lineHeight: 1.25);
      }
      top += heights[i];
    }
  }

  static void notes(Canvas c, DocumentFormLayout layout,
      {required String remark, required double remarkFontSize,
      String delivery = '', Color? deliveryColor}) {
    final top = layout.summaryTop;
    box(c, Rect.fromLTWH(0, top, DocumentFormStyle.remarkBoxWidth, layout.summaryHeight),
      const Color(0xFFFBFCFD));
    box(c, Rect.fromLTWH(DocumentFormStyle.deliveryLeft, top,
      DocumentFormStyle.deliveryBoxWidth, layout.summaryHeight), const Color(0xFFF3F8FC));
    DocumentFormStyle.drawText(c, 'Remark/비고',
      Rect.fromLTWH(12, top + 8, DocumentFormStyle.remarkWidth, 32), 23, bold: true);
    DocumentFormStyle.drawText(c, 'Inland delivery/시내·지방 배송',
      Rect.fromLTWH(DocumentFormStyle.deliveryLeft + 12, top + 8,
        DocumentFormStyle.deliveryWidth, 32), 23, bold: true);
    DocumentFormStyle.drawText(c, remark.trim().isEmpty ? '-' : remark.trim(),
      Rect.fromLTWH(12, top + 52, DocumentFormStyle.remarkWidth, layout.summaryHeight - 68),
      remarkFontSize, center: true, top: true, lineHeight: 1.45);
    if (deliveryColor != null && delivery.trim().isNotEmpty) {
      c.drawRect(Rect.fromLTWH(DocumentFormStyle.deliveryLeft + 6, top + 46,
        DocumentFormStyle.deliveryBoxWidth - 12, layout.summaryHeight - 52),
        Paint()..color = deliveryColor.withOpacity(.32));
    }
    DocumentFormStyle.drawText(c, delivery.trim().isEmpty ? '-' : delivery.trim(),
      Rect.fromLTWH(DocumentFormStyle.deliveryLeft + 12, top + 52,
        DocumentFormStyle.deliveryWidth, layout.summaryHeight - 68),
      DocumentFormStyle.deliveryFontSize, bold: true, center: true,
      top: true, lineHeight: 1.35);
  }

  static void totals(Canvas c, DocumentFormLayout layout,
      {required List<(String, String, String)> adjustments,
      required String label, required List<String> amounts}) {
    assert(adjustments.length == 4 && amounts.length == 4);
    const left = DocumentFormStyle.totalsLeft;
    const w = DocumentFormStyle.contentWidth - left;
    const adjustmentHeight = 42.0;
    for (var i = 0; i < adjustments.length; i++) {
      final r = Rect.fromLTWH(left, layout.summaryTop + i * adjustmentHeight, w, adjustmentHeight);
      box(c, r, Colors.white);
      final row = adjustments[i];
      DocumentFormStyle.drawText(c, row.$1,
        Rect.fromLTWH(left + 10, r.top + 3, w * .46 - 10, r.height - 6), 18, bold: true);
      DocumentFormStyle.drawText(c, row.$2,
        Rect.fromLTWH(left + w * .48, r.top + 3, w * .18, r.height - 6), 18,
        bold: true, center: true);
      DocumentFormStyle.drawText(c, row.$3,
        Rect.fromLTWH(left + w * .67, r.top + 3, w * .33 - 10, r.height - 6), 18,
        bold: true, right: true);
    }
    final top = layout.summaryTop + adjustmentHeight * 4;
    final height = layout.summaryHeight - adjustmentHeight * 4;
    const labelWidth = w * .38;
    box(c, Rect.fromLTWH(left, top, labelWidth, height), DocumentFormStyle.totalLabel);
    DocumentFormStyle.drawText(c, label,
      Rect.fromLTWH(left + 8, top + 6, labelWidth - 16, height - 12), 22,
      center: true, bold: true);
    const currencies = ['USD', 'KIP', 'THB', 'KRW'];
    const fills = [DocumentFormStyle.currencyUsd, DocumentFormStyle.currencyKip,
      DocumentFormStyle.currencyThb, DocumentFormStyle.currencyKrw];
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH(left + labelWidth, top + i * height / 4, w - labelWidth, height / 4);
      box(c, r, fills[i]);
      DocumentFormStyle.drawText(c, currencies[i],
        Rect.fromLTWH(r.left + 10, r.top + 2, 54, r.height - 4), 20, bold: true);
      money(c, amounts[i],
        Rect.fromLTRB(r.left + 64, r.top + 2, r.right - 8, r.bottom - 2), 20);
    }
  }

  // The bundled Korean and Lao fonts both omit U+0E3F (Thai Baht).
  // Render its standard B-and-stem form with the document font so exported
  // amounts do not depend on platform fallback fonts or new bundled assets.
  static void money(Canvas c, String amount, Rect rect, double fontSize) {
    if (!amount.startsWith('฿ ')) {
      DocumentFormStyle.drawText(c, amount, rect, fontSize, bold: true, right: true);
      return;
    }
    final painter = DocumentFormStyle.textPainter(
      amount.replaceFirst('฿', 'B'), fontSize, rect.width,
      bold: true, align: TextAlign.right);
    final scale = painter.height > rect.height ? rect.height / painter.height : 1.0;
    c.save();
    c.translate(rect.right - painter.width * scale,
      rect.top + (rect.height - painter.height * scale) / 2);
    c.scale(scale);
    painter.paint(c, Offset.zero);
    final glyph = painter.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1)).first;
    final stemX = glyph.left + (glyph.right - glyph.left) * .42;
    c.drawLine(Offset(stemX, glyph.top + fontSize * .04),
      Offset(stemX, glyph.bottom - fontSize * .04),
      Paint()..color = DocumentFormStyle.ink..strokeWidth = fontSize * .065);
    c.restore();
    painter.dispose();
  }

  static void footer(Canvas c, DocumentFormLayout layout,
      {required ui.Image qrUsd, required ui.Image qrKip, required ui.Image qrThb,
      required ui.Image stamp, required String footerText, required double footerFontSize,
      required double kipRate, required double thbRate, required double krwRate}) {
    const w = DocumentFormStyle.contentWidth;
    const payW = (w - DocumentFormStyle.sectionGap * 3) / 4;
    final qrs = [qrUsd, qrKip, qrThb];
    const titles = ['BCEL (USD):', 'BCEL (KIP):', 'BCEL (Baht):'];
    const accounts = ['010-12-01-', '013-12-00-', '010-12-02-'];
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH(i * (payW + DocumentFormStyle.sectionGap),
        layout.paymentTop, payW, DocumentFormStyle.paymentHeight);
      box(c, r, Colors.white);
      if (i < 3) {
        image(c, qrs[i], Rect.fromLTWH(r.left + 10, r.top + 12, 120, 120));
        DocumentFormStyle.drawText(c,
          '${titles[i]}\n(SungHo Park)\n${accounts[i]}\n017655-60-001',
          Rect.fromLTWH(r.left + 140, r.top + 8, r.width - 148, r.height - 16),
          20, bold: true, center: true, lineHeight: 1.25);
      } else {
        DocumentFormStyle.drawText(c, '한국 원화 계좌:\n경남은행\n571-22-0330221\n박성호',
          r.deflate(8), 20, bold: true, center: true, lineHeight: 1.35);
      }
    }
    final top = layout.signTop;
    final height = layout.signHeight;
    const signW = DocumentFormStyle.signatureWidth;
    box(c, Rect.fromLTWH(0, top, signW, height), Colors.white);
    box(c, Rect.fromLTWH(DocumentFormStyle.footerLeft, top,
      DocumentFormStyle.footerBoxWidth, height), Colors.white);
    box(c, Rect.fromLTWH(w - signW, top, signW, height), Colors.white);
    image(c, stamp, Rect.fromLTWH(54, top + 4, signW - 62, height - 8));
    DocumentFormStyle.drawText(c, '엘케이(LK)무역',
      Rect.fromLTWH(12, top + 10, signW - 24, 28), 21, bold: true, top: true);
    DocumentFormStyle.drawText(c, footerText,
      Rect.fromLTWH(DocumentFormStyle.footerLeft + 12, top + 12,
        DocumentFormStyle.footerWidth, height - 24), footerFontSize,
      center: true, top: true, lineHeight: 1.25);
    DocumentFormStyle.drawText(c, '고객사 확인',
      Rect.fromLTWH(w - signW + 12, top + 10, signW - 24, 28), 21, bold: true, top: true);
    final number = NumberFormat('#,##0.##', 'en_US');
    DocumentFormStyle.drawText(c,
      '적용 환율 · 1 USD = ${number.format(kipRate)} LAK · 1 USD = ${number.format(thbRate)} THB · 1 USD = ${number.format(krwRate)} KRW',
      Rect.fromLTWH(0, layout.rateNoteTop, w, 28), 17, right: true);
  }
}
