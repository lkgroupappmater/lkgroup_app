import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/document_form_painter.dart';
import '../lib/core/document_delivery_style.dart';
import '../lib/core/document_form_style.dart';
import '../lib/core/document_text_catalog.dart';
import '../lib/core/route_catalog.dart';
import '../lib/screens/quotation_preview_dialog.dart';
import '../lib/screens/statement_preview_dialog.dart';
import '../lib/services/exchange_rate_service.dart';
import '../lib/services/freight_service.dart';
import '../lib/services/quote_freight_calculator.dart';
import '../lib/services/receipt_extra_cost_service.dart';

// Exercise the production PNG/PDF painters with real bundled fonts and images.
// Fixtures are synthetic and require no account, network or shipment database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<ui.Image> assets;
  final date = DateTime(2026, 9, 12);
  const rates = ExchangeRateSettings(baseKip: 24276, baseThb: 34.56,
    baseKrw: 1385, kipAdjustment: 0, thbAdjustment: 0, krwAdjustment: 0);
  const quoteLine = QuoteBoxFreightResult(index: 1, actualWeightKg: 10,
    volumeWeightKg: 2.904, chargeableWeightKg: 10, ratePerKg: 1.5,
    quantity: 1, amountUsd: 15, movingCargoSurchargeUsd: 0, boxPackingSurchargeUsd: 0);
  const quoteBox = QuotationPreviewBox(index: 1, weightKg: 10,
    lengthCm: 55, widthCm: 20, heightCm: 12, quantity: 1, result: quoteLine);

  setUpAll(() async {
    await (FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.otf'))).load();
    await (FontLoader('PhetsarathOT')
      ..addFont(rootBundle.load('assets/fonts/phetsarath_ot.ttf'))).load();
    assets = await Future.wait([
      'company_logo_transparent.png', 'payment_qr_usd.png', 'payment_qr_kip.png',
      'payment_qr_thb.png', 'company_stamp.png', 'bank_accounts_strip.png',
    ].map((name) async {
      final data = await rootBundle.load('assets/images/$name');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    }));
  });
  tearDownAll(() { for (final asset in assets) { asset.dispose(); } });

  DigitalQuotationPainter quotation(String route, {double discount = 0,
      List<ExtraCostItem> extras = const []}) => DigitalQuotationPainter(
    routeLabel: route, boxes: const [quoteBox],
    result: QuoteFreightResult(route: route, lines: const [quoteLine],
      totalUsd: 15, sourceFile: 'synthetic-print-fixture'),
    rates: rates, extraCosts: extras, discountPercent: discount, issuedAt: date,
    logo: assets[0], qrUsd: assets[1], qrKip: assets[2], qrThb: assets[3],
    stamp: assets[4], bankStrip: assets[5]);

  DigitalStatementPainter statement(String route, {double discount = .05,
      String delivery = '', int count = 3, List<ExtraCostItem> extras = const []}) {
    const weights = [2.8, 6.4, .2];
    const volumes = [6.89, 19.6, .04];
    const grosses = [10.335, 29.4, 1.5];
    final lines = List.generate(count, (i) {
      final gross = grosses[i % 3];
      return FreightLineResult(shipmentId: 'fixture-$i', boxNumber: 'S${i+1}',
        invoiceNumber: 'LKS 01', route: route, actualWeight: weights[i % 3],
        volumeWeight: volumes[i % 3], chargeableWeight: gross / 1.5, rate: 1.5,
        amountUsd: gross * (1-discount), grossAmountUsd: gross,
        discountPercent: discount, discountAmountUsd: gross * discount,
        autoDiscountPercent: discount, autoDiscountAmountUsd: gross * discount,
        discountGroup: discount == 1 ? '대표 고정 할인' : '기업 할인');
    });
    final gross = lines.fold<double>(0, (sum, line) => sum + line.grossAmountUsd);
    final total = gross * (1-discount);
    final rows = List.generate(count, (i) => <String, dynamic>{
      'id': 'fixture-$i', 'box_number': 'S${i+1}', 'quantity': 1,
      'length_cm': i % 3 == 2 ? 15 : 24, 'width_cm': i % 3 == 2 ? 11 : 29,
      'height_cm': i % 3 == 2 ? 1 : 45, 'consignee_name': '출력 검토 고객',
      'consignee_phone': '-', 'unloading_zone': 'A',
      'special_note_auto': '카톡 명세서 선공유 및 온라인 결제${delivery.isEmpty ? '' : ' / 지방배송(선결제)'}',
    });
    return DigitalStatementPainter(routeLabel: route, rows: rows,
      freight: FreightCalculation(lines: lines, totalUsd: total,
        totalKip: total*rates.appliedKip, totalThb: total*rates.appliedThb,
        totalKrw: total*rates.appliedKrw, rates: rates,
        grossTotalUsd: gross, discountTotalUsd: gross*discount),
      receiptNumber: 'LKS 01', voyage: '08', inlandDeliveryText: delivery,
      extraCosts: extras, logo: assets[0], qrUsd: assets[1], qrKip: assets[2],
      qrThb: assets[3], stamp: assets[4], bankStrip: assets[5]);
  }

  Future<({ui.Image image, Uint8List rgba})> render(CustomPainter painter,
      double height, String name) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Size(DocumentFormStyle.width, height));
    final picture = recorder.endRecording();
    final image = await picture.toImage(1800, height.ceil());
    picture.dispose();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/document-previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (image: image, rgba: rgba!.buffer.asUint8List());
  }

  int pixel(Uint8List data, double x, double y) {
    final offset = (y.floor()*1800 + x.floor())*4;
    return (data[offset]<<16) | (data[offset+1]<<8) | data[offset+2];
  }
  int pixelsWhere(Uint8List data, Rect region, bool Function(int color) predicate) {
    var count = 0;
    for (var y = region.top.ceil(); y < region.bottom.floor(); y++) {
      for (var x = region.left.ceil(); x < region.right.floor(); x++) {
        if (predicate(pixel(data, x.toDouble(), y.toDouble()))) count++;
      }
    }
    return count;
  }
  void checkPrintedFurniture(Uint8List data, DocumentFormLayout layout) {
    const pad = DocumentFormStyle.pagePadding;
    final cols = DocumentFormStyle.columns;
    for (final pair in [(5, 0xFFE49A), (10, 0xCFE8BD), (13, 0xBFDDF1)]) {
      expect(pixel(data, pad+cols[pair.$1]+6, pad+DocumentFormStyle.tableTop+6), pair.$2);
    }
    // Empty rows are really empty, including the old preprinted row numbers.
    final blank = Rect.fromLTRB(pad+5, pad+layout.rowTop(layout.itemCount)+4,
      pad+cols[1]-5, pad+layout.rowTop(layout.itemCount)+layout.rowHeightAt(layout.itemCount)-4);
    expect(pixelsWhere(data, blank, (c) => c != 0xFFFFFF), 0);
    final currencyH = (layout.summaryHeight-168)/4;
    for (var i=0; i<4; i++) {
      final x = pad+DocumentFormStyle.totalsLeft+
        (DocumentFormStyle.contentWidth-DocumentFormStyle.totalsLeft)*.38+4;
      expect(pixel(data, x, pad+layout.summaryTop+168+i*currencyH+4),
        [0xFCE48A, 0xFFC21A, 0x91D18B, 0x23B6D8][i]);
    }
    const payW = (DocumentFormStyle.contentWidth-24)/4;
    for (var i=0; i<3; i++) {
      final qr = Rect.fromLTWH(pad+i*(payW+8)+10, pad+layout.paymentTop+12, 120, 120);
      expect(pixelsWhere(data, qr, (c) => ((c>>16)&255)<100 && ((c>>8)&255)<100 && (c&255)<100),
        greaterThan(800), reason: 'QR $i must be drawn');
    }
    final seal = Rect.fromLTWH(pad+60, pad+layout.signTop+4, 240, layout.signHeight-8);
    expect(pixelsWhere(data, seal, (c) => (c&255)>120 && ((c>>16)&255)<100),
      greaterThan(1000), reason: 'the enlarged blue stamp must be drawn');
  }

  test('delivery tint is drawn for every type and absent on empty estimates', () async {
    final layout = DocumentFormLayout(itemCount: 1, remark: '', remarkFontSize: 22,
      footer: '', footerFontSize: 17);
    for (final color in [DocumentDeliveryStyle.province, DocumentDeliveryStyle.city,
        DocumentDeliveryStyle.provincePrepaid, DocumentDeliveryStyle.cityPrepaid]) {
      for (final delivery in ['배송 검토 고객', '']) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.translate(18, 18);
        DocumentFormPainter.notes(canvas, layout, remark: '', remarkFontSize: 22,
          delivery: delivery, deliveryColor: color);
        final picture = recorder.endRecording();
        final img = await picture.toImage(1800, layout.height.ceil());
        picture.dispose();
        final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        final expected = delivery.isEmpty ? const Color(0xFFF3F8FC)
            : Color.alphaBlend(color.withOpacity(.32), const Color(0xFFF3F8FC));
        expect(pixel(bytes, 18+DocumentFormStyle.deliveryLeft+8, 18+layout.summaryTop+48),
          expected.value & 0xFFFFFF);
        img.dispose();
      }
    }
  });

  test('all eleven route quotation and statement exports use the web form', () async {
    expect(RouteCatalog.routes.length, 11);
    for (final route in RouteCatalog.routes) {
      final key = RouteCatalog.keyFor(route);
      final q = quotation(route);
      final qText = DocumentTextCatalog.quotation(route, date);
      final qLayout = DocumentFormLayout(itemCount: 1, remark: qText.remark,
        remarkFontSize: qText.remarkFontSize, footer: qText.footerText,
        footerFontSize: qText.footerFontSize);
      final qr = await render(q, q.documentHeight, '${key}_quotation');
      checkPrintedFurniture(qr.rgba, qLayout);
      // Actual weight wins for the quotation; volume wins in the statement.
      final cols = DocumentFormStyle.columns;
      expect(pixel(qr.rgba, 18+cols[11]+6, 18+qLayout.rowTop(0)+6), 0xFFE49A);
      expect(pixel(qr.rgba, 18+cols[12]+6, 18+qLayout.rowTop(0)+6), 0xFFFFFF);
      qr.image.dispose();
      final s = statement(route);
      final sText = DocumentTextCatalog.statement(route, DateTime.now());
      final sLayout = DocumentFormLayout(itemCount: 3,
        remark: '${sText.remark}\n\n카톡 명세서 선공유 및 온라인 결제 / 기업 할인 5% 적용',
        remarkFontSize: sText.remarkFontSize, footer: sText.footerText,
        footerFontSize: sText.footerFontSize);
      final sr = await render(s, s.documentHeight, '${key}_statement');
      expect(s.documentHeight, sLayout.height);
      checkPrintedFurniture(sr.rgba, sLayout);
      expect(pixel(sr.rgba, 18+cols[12]+6, 18+sLayout.rowTop(0)+6), 0xCFE8BD);
      expect(pixel(sr.rgba, 18+cols[11]+6, 18+sLayout.rowTop(0)+6), 0xFFFFFF);
      sr.image.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('100 percent and selective extra-cost discounts retain printed amounts', () async {
    final route = RouteCatalog.routes.first;
    const extras = [ExtraCostItem(name: '할인 적용 부대비', amountUsd: 5, discountApplies: true),
      ExtraCostItem(name: '별도 배송비', amountUsd: 7)];
    final q = quotation(route, discount: 100, extras: extras);
    final doc = DocumentTextCatalog.quotation(route, date);
    final layout = DocumentFormLayout(itemCount: 3, remark: doc.remark,
      remarkFontSize: doc.remarkFontSize, footer: doc.footerText, footerFontSize: doc.footerFontSize);
    final rendered = await render(q, q.documentHeight, 'quotation_100_percent_extras');
    // Compare the actual financial panel with independently specified values:
    // 15 freight + 5 discountable + 7 excluded = 27, discount 20, payable 7.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, 1800, q.documentHeight), Paint()..color = Colors.white);
    canvas.translate(18, 18);
    DocumentFormPainter.totals(canvas, layout, adjustments: [
      ('운임 총합', '', '27.00'), ('할인', '100%', '-20.00'),
      ('추가 할인', '-', '-'), ('세금 계산서(VAT)', '-', '-'),
    ], label: '최종 가견적 총액', amounts: ['7.00', '170,000', '242', '9,700']);
    final picture = recorder.endRecording();
    final expected = await picture.toImage(1800, q.documentHeight.ceil());
    picture.dispose();
    final expectedBytes = (await expected.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    for (var y = (18+layout.summaryTop+2).ceil(); y < 18+layout.summaryTop+layout.summaryHeight-2; y++) {
      final start = (y*1800+(18+DocumentFormStyle.totalsLeft+2).ceil())*4;
      final end = (y*1800+1780)*4;
      expect(rendered.rgba.sublist(start, end), expectedBytes.sublist(start, end), reason: 'financial row $y');
    }
    expected.dispose();
    rendered.image.dispose();
    final s = statement(route, discount: 1, extras: extras,
      delivery: 'No. 19\n출력 검토 수취인 / ລາວ\n020-0000-0000\nANS\n지방배송(선결제)');
    final sr = await render(s, s.documentHeight, 'statement_100_percent_delivery');
    sr.image.dispose();
  });

  test('many cargo rows and long Lao delivery text remain in the image', () async {
    final s = statement(RouteCatalog.routes[2], count: 35,
      delivery: List.filled(25, 'ການຂົນສົ່ງ 배송 주소와 수취인 안내').join('\n'));
    expect(s.documentHeight, greaterThan(2200));
    final result = await render(s, s.documentHeight, 'statement_long_delivery');
    expect(result.image.height, s.documentHeight.ceil());
    result.image.dispose();
  });
}
