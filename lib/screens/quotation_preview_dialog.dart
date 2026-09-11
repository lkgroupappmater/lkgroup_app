import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money_format.dart';
import '../core/route_catalog.dart';
import '../core/document_text_catalog.dart';
import '../core/document_form_style.dart';
import '../core/document_form_painter.dart';
import '../services/document_pdf_export.dart';
import '../services/exchange_rate_service.dart';
import '../services/quote_freight_calculator.dart';
import '../services/receipt_extra_cost_service.dart';


double _d(dynamic value, [double fallback = 0]) =>
    double.tryParse('${value ?? ''}'.trim()) ?? fallback;

String _s(dynamic value) => '${value ?? ''}'.trim();

String _fmtWeight(double v) {
  if ((v - v.roundToDouble()).abs() < .001) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}


class QuotationPreviewBox {
  const QuotationPreviewBox({
    required this.index,
    required this.weightKg,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.quantity,
    required this.result,
  });

  final int index;
  final double weightKg;
  final double lengthCm;
  final double widthCm;
  final double heightCm;
  final int quantity;
  final QuoteBoxFreightResult result;
}

class QuotationPreviewDialog extends StatefulWidget {
  const QuotationPreviewDialog({
    super.key,
    required this.routeLabel,
    required this.boxes,
    required this.result,
    required this.rates,
    this.extraCosts = const <ExtraCostItem>[],
    this.discountPercent = 0,
  });

  final String routeLabel;
  final List<QuotationPreviewBox> boxes;
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;

  final List<ExtraCostItem> extraCosts;
  final double discountPercent;
  @override
  State<QuotationPreviewDialog> createState() => _QuotationPreviewDialogState();
}

class _QuotationPreviewDialogState extends State<QuotationPreviewDialog> {
  ui.Image? _logo;
  ui.Image? _qrUsd;
  ui.Image? _qrKip;
  ui.Image? _qrThb;
  ui.Image? _stamp;
  ui.Image? _bankStrip;
  bool _loading = true;
  bool _saving = false;
  late final DateTime _issuedAt;

  static const double _docWidth = DocumentFormStyle.width;
  double get _docHeight => _painter.documentHeight;

  @override
  void initState() {
    super.initState();
    _issuedAt = DateTime.now();
    _loadAssets();
  }

  @override
  void dispose() {
    _logo?.dispose();
    _qrUsd?.dispose();
    _qrKip?.dispose();
    _qrThb?.dispose();
    _stamp?.dispose();
    _bankStrip?.dispose();
    super.dispose();
  }

  Future<ui.Image> _assetImage(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<void> _loadAssets() async {
    try {
      final assets = await Future.wait<ui.Image>([
        _assetImage('assets/images/company_logo_transparent.png'),
        _assetImage('assets/images/payment_qr_usd.png'),
        _assetImage('assets/images/payment_qr_kip.png'),
        _assetImage('assets/images/payment_qr_thb.png'),
        _assetImage('assets/images/company_stamp.png'),
        _assetImage('assets/images/bank_accounts_strip.png'),
      ]);
      if (!mounted) return;
      setState(() {
        _logo = assets[0];
        _qrUsd = assets[1];
        _qrKip = assets[2];
        _qrThb = assets[3];
        _stamp = assets[4];
        _bankStrip = assets[5];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('견적서 리소스 로딩 실패: $e')));
    }
  }

  DigitalQuotationPainter get _painter => DigitalQuotationPainter(
        routeLabel: widget.routeLabel,
        boxes: widget.boxes,
        result: widget.result,
        rates: widget.rates,
        extraCosts: widget.extraCosts,
        discountPercent: widget.discountPercent,
        issuedAt: _issuedAt,
        logo: _logo!,
        qrUsd: _qrUsd!,
        qrKip: _qrKip!,
        qrThb: _qrThb!,
        stamp: _stamp!,
        bankStrip: _bankStrip!,
      );

  String _two(int v) => v.toString().padLeft(2, '0');

  Future<Uint8List> _renderPng() async {
    if (_logo == null) throw StateError('견적서 리소스가 준비되지 않았습니다.');
    const scale = 1.5;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    _painter.paint(canvas, Size(_docWidth, _docHeight));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (_docWidth * scale).round(),
      (_docHeight * scale).round(),
    );
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('PNG 변환에 실패했습니다.');
    return data.buffer.asUint8List();
  }

  Future<void> _saveImage() async {
    setState(() => _saving = true);
    try {
      final bytes = await _renderPng();
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final name =
          '${prefix.isEmpty ? 'QUOTATION' : prefix}_QUOTATION_${_issuedAt.year}${_two(_issuedAt.month)}${_two(_issuedAt.day)}.png';
      final path = await FilePicker.saveFile(
        dialogTitle: '가견적서 이미지 저장',
        fileName: name,
        bytes: bytes,
        mimeType: 'image/png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path == null ? '저장을 취소했습니다.' : '가견적서 이미지를 저장했습니다.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('이미지 저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePdf() async {
    setState(() => _saving = true);
    try {
      final png = await _renderPng();
      final pdf = await DocumentPdfExport.quotation(
        png,
        sourceWidth: _docWidth,
        sourceHeight: _docHeight,
      );
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final name =
          '${prefix.isEmpty ? 'QUOTATION' : prefix}_QUOTATION_${_issuedAt.year}${_two(_issuedAt.month)}${_two(_issuedAt.day)}.pdf';
      final path = await FilePicker.saveFile(
        dialogTitle: '가견적서 출력용 PDF 저장',
        fileName: name,
        bytes: pdf,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path == null ? '저장을 취소했습니다.' : '출력용 PDF를 저장했습니다.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF 저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && _logo != null && _stamp != null && _bankStrip != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * .99,
        height: MediaQuery.sizeOf(context).height * .95,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.routeLabel} · 가견적서',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Container(
                color: const Color(0xFFEDF2F7),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : !ready
                        ? const Center(
                            child: Text('가견적서를 불러오지 못했습니다.',
                                style: TextStyle(color: Colors.white)),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final width = (constraints.maxWidth - 8).clamp(280.0, 1800.0);
                              final height = width * _docHeight / _docWidth;
                              return InteractiveViewer(
                                minScale: .7,
                                maxScale: 4,
                                constrained: false,
                                boundaryMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  child: SizedBox(
                                    width: width,
                                    height: height,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: SizedBox(
                                        width: _docWidth,
                                        height: _docHeight,
                                        child: CustomPaint(painter: _painter),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: !ready || _saving ? null : _saveImage,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('이미지 저장'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: !ready || _saving ? null : _savePdf,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('출력용 PDF'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DigitalQuotationPainter extends CustomPainter {
  const DigitalQuotationPainter({
    required this.routeLabel,
    required this.boxes,
    required this.result,
    required this.rates,
    required this.extraCosts,
    required this.discountPercent,
    required this.issuedAt,
    required this.logo,
    required this.qrUsd,
    required this.qrKip,
    required this.qrThb,
    required this.stamp,
    required this.bankStrip,
  });

  final String routeLabel;
  final List<QuotationPreviewBox> boxes;
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;
  final List<ExtraCostItem> extraCosts;
  final double discountPercent;
  final DateTime issuedAt;
  final ui.Image logo;
  final ui.Image qrUsd;
  final ui.Image qrKip;
  final ui.Image qrThb;
  final ui.Image stamp;
  final ui.Image bankStrip;

  static const ink = DocumentFormStyle.ink;
  static const line = DocumentFormStyle.line;
  static const paleBlue = DocumentFormStyle.paleBlue;
  static const actualColor = DocumentFormStyle.actual;
  static const volumeColor = DocumentFormStyle.volume;
  static const appliedColor = DocumentFormStyle.applied;
  static const totalColor = DocumentFormStyle.total;

  DocumentTextContent get _docText => DocumentTextCatalog.quotation(routeLabel, issuedAt);
  String get _remarkText => _docText.remark;

  DocumentFormLayout get _layout => DocumentFormLayout(
    itemCount: boxes.length + extraCosts.length,
    remark: _remarkText, remarkFontSize: _docText.remarkFontSize,
    footer: _docText.footerText, footerFontSize: _docText.footerFontSize,
  );
  double get documentHeight => _layout.height;

  @override
  void paint(Canvas c, Size size) {
    final layout = _layout;
    final safeDiscountPercent =
        discountPercent.clamp(0, 100).toDouble();
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    c.save();
    c.translate(DocumentFormStyle.pagePadding, DocumentFormStyle.pagePadding);
    DocumentFormPainter.header(c, logo: logo,
      title: '${RouteCatalog.documentTitleFor(routeLabel)} 가견적서',
      zone: '-', customer: '-', phone: '-', lastLabel: '견적일',
      lastValue: '${issuedAt.year}-${issuedAt.month.toString().padLeft(2, '0')}-${issuedAt.day.toString().padLeft(2, '0')}');

    const tableTop = DocumentFormStyle.tableTop;
    const headerH = DocumentFormStyle.headerHeight;
    const rowH = DocumentFormStyle.totalsRowHeight;
    final rowCount = layout.rowCount;
    final cols = DocumentFormStyle.columns;
    final headers = <String>[
      'No.', '박스번호', '단가', '수량', '실제중량\n(kg)', '실제중량 합산\n(kg)',
      'L', 'W', 'H', '용적중량\n(kg)', '용적중량 합산\n(kg)',
      '실제중량 운임', '용적중량 운임', '청구중량 운임'
    ];
    final fills = <Color?>[
      null, null, null, null, null, actualColor, null, null, null, null,
      volumeColor, actualColor, volumeColor, appliedColor
    ];

    for (var i = 0; i < headers.length; i++) {
      final r = Rect.fromLTRB(cols[i], tableTop, cols[i + 1], tableTop + headerH);
      _box(c, r, fills[i] ?? const Color(0xFFF6F7F9));
      _text(c, headers[i], r.deflate(3), 18, bold: true, center: true);
    }

    for (var i = 0; i < rowCount; i++) {
      final y = layout.rowTop(i);
      final rowH = layout.rowHeightAt(i);
      final has = i < boxes.length;
      final extraIndex = i - boxes.length;
      final hasExtra = extraIndex >= 0 && extraIndex < extraCosts.length;
      final b = has ? boxes[i] : null;
      final actualWins =
          b != null && b.result.actualWeightKg >= b.result.volumeWeightKg;
      final volumeWins =
          b != null && b.result.volumeWeightKg > b.result.actualWeightKg;

      for (var col = 0; col < headers.length; col++) {
        Color fill = Colors.white;
        if (has && col == 11 && actualWins) fill = actualColor;
        if (has && col == 12 && volumeWins) fill = volumeColor;
        if ((has || hasExtra) && col == 13) fill = appliedColor;
        _box(c, Rect.fromLTRB(cols[col], y, cols[col + 1], y + rowH), fill);
      }
      if (has || hasExtra) _text(c, '${i + 1}',
          Rect.fromLTRB(cols[0] + 3, y + 2, cols[1] - 3, y + rowH - 2),
          18, center: true);
      if (hasExtra) {
        final extra = extraCosts[extraIndex];
        _box(c, Rect.fromLTRB(cols[1], y, cols[13], y + rowH), const Color(0xFFF8FAFD));
        _text(
          c,
          '${extra.name}${extra.discountApplies && safeDiscountPercent > 0 ? ' (할인)' : ''}',
          Rect.fromLTRB(cols[1] + 12, y + 2, cols[13] - 12, y + rowH - 2),
          19,
          bold: true,
          center: false,
        );
        _text(
          c,
          MoneyFormat.usd(extra.amountUsd),
          Rect.fromLTRB(cols[13] + 3, y + 2, cols[14] - 3, y + rowH - 2),
          19,
          bold: true,
          center: true,
        );
        continue;
      }
      if (!has || b == null) continue;

      final qty = b.quantity < 1 ? 1 : b.quantity;
      final unitActual = b.result.actualWeightKg / qty;
      final unitVolume = b.result.volumeWeightKg / qty;
      final actualFreight = b.result.actualWeightKg * b.result.ratePerKg;
      final volumeFreight = b.result.volumeWeightKg * b.result.ratePerKg;
      final values = <String>[
        'Q${i + 1}',
        '\$ ${b.result.ratePerKg.toStringAsFixed(2)}',
        '$qty',
        _fmtWeight(unitActual),
        _fmtWeight(b.result.actualWeightKg),
        _fmtWeight(b.lengthCm),
        _fmtWeight(b.widthCm),
        _fmtWeight(b.heightCm),
        _fmtWeight(unitVolume),
        _fmtWeight(b.result.volumeWeightKg),
        MoneyFormat.usd(actualFreight),
        MoneyFormat.usd(volumeFreight),
        MoneyFormat.usd(b.result.amountUsd),
      ];
      for (var col = 0; col < values.length; col++) {
        _text(c, values[col],
            Rect.fromLTRB(cols[col + 1] + 3, y + 2, cols[col + 2] - 3, y + rowH - 2),
            19,
            bold: col == 0 || col == 12 || (col == 10 && actualWins) || (col == 11 && volumeWins),
            center: true);
      }
    }

    final summaryY = layout.tableTotalTop;
    for (var col = 0; col < headers.length; col++) {
      _box(c, Rect.fromLTRB(cols[col], summaryY, cols[col + 1], summaryY + rowH),
          col >= 11 ? paleBlue : const Color(0xFFF2F5F8));
    }
    final totalQty = boxes.fold<double>(0, (v, b) => v + b.quantity);
    final totalActual = boxes.fold<double>(0, (v, b) => v + b.result.actualWeightKg);
    final totalVolume = boxes.fold<double>(0, (v, b) => v + b.result.volumeWeightKg);
    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final discountableExtra = extraCosts
        .where((e) => e.discountApplies)
        .fold<double>(0, (sum, e) => sum + e.amountUsd);
    final grossUsd = result.totalUsd + extraTotal;
    final discountBase = result.totalUsd + discountableExtra;
    final discountAmount = discountBase * safeDiscountPercent / 100;
    final usd = grossUsd - discountAmount;
    final summaryValues = <int, String>{
      1: '합계',
      3: _fmtWeight(totalQty),
      5: _fmtWeight(totalActual),
      10: _fmtWeight(totalVolume),
      13: MoneyFormat.usd(grossUsd),
    };
    for (final e in summaryValues.entries) {
      _text(c, e.value,
          Rect.fromLTRB(cols[e.key] + 4, summaryY + 2, cols[e.key + 1] - 4, summaryY + rowH - 2),
          18, bold: true, center: true);
    }

    final docText = _docText;
    DocumentFormPainter.notes(c, layout,
      remark: docText.remark, remarkFontSize: docText.remarkFontSize);
    final discountLabel = safeDiscountPercent > 0
        ? '${safeDiscountPercent.toStringAsFixed(safeDiscountPercent == safeDiscountPercent.roundToDouble() ? 0 : 1)}%'
        : '-';
    final discountValue =
        safeDiscountPercent > 0 ? '-${MoneyFormat.usd(discountAmount)}' : '-';

    DocumentFormPainter.totals(c, layout, adjustments: [
      ('운임 총합', '', MoneyFormat.usd(grossUsd)),
      ('할인', discountLabel, discountValue),
      ('추가 할인', '-', '-'),
      ('세금 계산서(VAT)', '-', '-'),
    ], label: '최종 가견적 총액', amounts: [
      MoneyFormat.usd(usd), MoneyFormat.kip(usd * rates.appliedKip),
      MoneyFormat.thb(usd * rates.appliedThb), MoneyFormat.krw(usd * rates.appliedKrw),
    ]);
    DocumentFormPainter.footer(c, layout, qrUsd: qrUsd, qrKip: qrKip,
      qrThb: qrThb, stamp: stamp, footerText: docText.footerText,
      footerFontSize: docText.footerFontSize,
      kipRate: rates.appliedKip, thbRate: rates.appliedThb, krwRate: rates.appliedKrw);
    c.restore();
  }

  void _box(Canvas c, Rect r, Color fill) => DocumentFormPainter.box(c, r, fill);

  void _text(Canvas c, String text, Rect r, double size,
      {bool bold = false, bool center = false, bool right = false, double lineHeight = 1.15}) {
    DocumentFormStyle.drawText(c, text, r, size,
        bold: bold, center: center, right: right, lineHeight: lineHeight);
  }

  @override
  bool shouldRepaint(covariant DigitalQuotationPainter oldDelegate) => true;
}










