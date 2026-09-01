import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money_format.dart';
import '../core/route_catalog.dart';
import '../core/document_text_catalog.dart';
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

  static const double _docWidth = 1800;
  int get _visibleRows => widget.boxes.length + widget.extraCosts.length + 1 < 10
      ? 10
      : widget.boxes.length + widget.extraCosts.length + 1;
  double get _docHeight => 1120 + (_visibleRows - 10) * 32;

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

  _DigitalQuotationPainter get _painter => _DigitalQuotationPainter(
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
                color: const Color(0xFF202124),
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

class _DigitalQuotationPainter extends CustomPainter {
  const _DigitalQuotationPainter({
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

  static const ink = Color(0xFF182433);
  static const line = Color(0xFF687A8C);
  static const paleBlue = Color(0xFFD9EAF7);
  static const actualColor = Color(0xFFFFE49A);
  static const volumeColor = Color(0xFFCFE8BD);
  static const appliedColor = Color(0xFFBFDDF1);
  static const totalColor = Color(0xFFFFE86A);

  @override
  void paint(Canvas c, Size size) {
    final safeDiscountPercent =
        discountPercent.clamp(0, 100).toDouble();
    final w = size.width;
    final h = size.height;
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _imageContain(c, logo, Rect.fromLTWH(18, 8, 135, 72));
    _text(c, '${RouteCatalog.documentTitleFor(routeLabel)} 가견적서',
        Rect.fromLTWH(0, 12, w, 62), 39, bold: true, center: true);
    _labelValue(c, '구획(Zone)', '-', Rect.fromLTWH(w - 300, 8, 282, 72));

    final infoTop = 90.0;
    const infoH = 106.0;
    for (var r = 0; r < 3; r++) {
      final y = infoTop + r * (infoH / 3);
      _box(c, Rect.fromLTWH(0, y, w * .5, infoH / 3), paleBlue.withOpacity(.38));
      _box(c, Rect.fromLTWH(w * .5, y, w * .5, infoH / 3), paleBlue.withOpacity(.38));
    }
    _kv(c, '회사명', '엘케이(LK)무역', Rect.fromLTWH(8, infoTop + 4, w * .49, 28));
    _kv(c, '회사주소', '비엔티엔시, 씨싿따낙구, 싸판텅 느아 09, 11번 골목, 엘케이(LK) 빌딩, 1층 LK Trading', Rect.fromLTWH(8, infoTop + 39, w * .49, 28));
    _kv(c, '전화번호', '+856 20 9112 6780', Rect.fromLTWH(8, infoTop + 74, w * .49, 28));
    _kv(c, '견적일',
        '${issuedAt.year}-${issuedAt.month.toString().padLeft(2, '0')}-${issuedAt.day.toString().padLeft(2, '0')}',
        Rect.fromLTWH(w * .5, infoTop + 74, w * .49, 28));
    _kv(c, '고객명/회사명', '-', Rect.fromLTWH(w * .5, infoTop + 4, w * .49, 28));
    _kv(c, '연락처', '-', Rect.fromLTWH(w * .5, infoTop + 39, w * .49, 28));

    const tableTop = 205.0;
    const headerH = 42.0;
    const rowH = 32.0;
    final usedRows = boxes.length + extraCosts.length;
    final rowCount = usedRows + 1 < 10 ? 10 : usedRows + 1;
    final cols = <double>[
      0, 55, 170, 285, 365, 490, 620, 710, 800, 890, 1030, 1170, 1360, 1570, 1800
    ];
    final headers = <String>[
      'No.', '박스번호', '단가', '수량', '실제중량(kg)', '실제중량 합산(kg)',
      'L', 'W', 'H', '용적중량(kg)', '용적중량 합산(kg)',
      '실제중량 운임', '용적중량 운임', '청구중량 운임'
    ];
    final fills = <Color?>[
      null, null, null, null, null, actualColor, null, null, null, null, volumeColor,
      actualColor, volumeColor, appliedColor
    ];

    for (var i = 0; i < headers.length; i++) {
      final r = Rect.fromLTRB(cols[i], tableTop, cols[i + 1], tableTop + headerH);
      _box(c, r, fills[i] ?? const Color(0xFFF6F7F9));
      _text(c, headers[i], r.deflate(3), 17, bold: true, center: true);
    }

    for (var i = 0; i < rowCount; i++) {
      final y = tableTop + headerH + i * rowH;
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
        if (has && col == 13) fill = appliedColor;
        _box(c, Rect.fromLTRB(cols[col], y, cols[col + 1], y + rowH), fill);
      }
      _text(c, '${i + 1}',
          Rect.fromLTRB(cols[0] + 3, y + 2, cols[1] - 3, y + rowH - 2),
          15, bold: true, center: true);
      if (hasExtra) {
        final extra = extraCosts[extraIndex];
        _text(
          c,
          '${extra.name}${extra.discountApplies && safeDiscountPercent > 0 ? ' (할인)' : ''}',
          Rect.fromLTRB(cols[1] + 3, y + 2, cols[2] - 3, y + rowH - 2),
          17,
          bold: true,
          center: true,
        );
        _text(
          c,
          MoneyFormat.usd(extra.amountUsd),
          Rect.fromLTRB(cols[13] + 3, y + 2, cols[14] - 3, y + rowH - 2),
          20,
          bold: true,
          right: true,
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
        '\$${b.result.ratePerKg.toStringAsFixed(2)}',
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
            col >= 10 && col <= 12 ? 20 : 18,
            bold: col == 4 || col == 9 || col == 12,
            center: col < 10,
            right: col >= 10);
      }
    }

    final summaryY = tableTop + headerH + rowCount * rowH;
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
          16, bold: true, center: true);
    }

    final sumTop = summaryY + rowH + 10;
    final docText = DocumentTextCatalog.quotation(routeLabel, issuedAt);
    final leftW = w * .70;
    _box(c, Rect.fromLTWH(0, sumTop, leftW * .58, 160), const Color(0xFFFBFCFD));
    _box(c, Rect.fromLTWH(leftW * .58 + 4, sumTop, leftW * .42 - 4, 160), const Color(0xFFF3F8FC));
    _text(c, 'Remark/비고', Rect.fromLTWH(10, sumTop + 7, leftW * .58 - 20, 24),
        17, bold: true);
    _text(
      c,
      docText.remark,
      Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),
      docText.remarkFontSize,
      maxLines: 6,
      lineHeight: 1.05,
    );

    _text(c, 'Inland delivery/시내·지방 배송',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 7, leftW * .42 - 24, 24),
        18, bold: true);
    

    final totalX = leftW + 6;
    final totalW = w - totalX;

    _box(c, Rect.fromLTWH(totalX, sumTop, totalW, 190), totalColor);
    final adjH = 25.0;
    final discountLabel = safeDiscountPercent > 0
        ? '${safeDiscountPercent.toStringAsFixed(safeDiscountPercent == safeDiscountPercent.roundToDouble() ? 0 : 1)}%'
        : '-';
    final discountValue =
        safeDiscountPercent > 0 ? '-${MoneyFormat.usd(discountAmount)}' : '-';

    _text(c, '할인',
        Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .48, adjH),
        16, bold: true);
    _text(c, discountLabel,
        Rect.fromLTWH(totalX + totalW * .58, sumTop + 7, totalW * .18, adjH),
        16, bold: true, center: true);
    _text(c, discountValue,
        Rect.fromLTWH(totalX + totalW * .78, sumTop + 7, totalW * .18, adjH),
        16, bold: true, right: true);

    for (final row in <(String, double)>[
      ('특별할인', sumTop + 34),
      ('세금 계산서(VAT)', sumTop + 61),
    ]) {
      _text(c, row.$1,
          Rect.fromLTWH(totalX + 12, row.$2, totalW * .48, adjH),
          16, bold: true);
      _text(c, '-',
          Rect.fromLTWH(totalX + totalW * .58, row.$2, totalW * .18, adjH),
          16, bold: true, center: true);
      _text(c, '-',
          Rect.fromLTWH(totalX + totalW * .78, row.$2, totalW * .18, adjH),
          16, bold: true, right: true);
    }

    final finalTop = sumTop + 92;
    final labelW = totalW * .38;
    _box(c, Rect.fromLTWH(totalX, finalTop, labelW, 94), const Color(0xFFFFF200));
    _text(c, '최종 가견적 총액', Rect.fromLTWH(totalX + 8, finalTop + 6, labelW - 16, 82),
        19, bold: true, center: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 0 * 23.5, totalW - labelW, 23.5),
        const Color(0xFFFCE48A));
    _text(c, 'USD     ${MoneyFormat.usd(usd)}',
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 0 * 23.5, totalW - labelW - 16, 23.5),
        20, bold: true, right: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 1 * 23.5, totalW - labelW, 23.5),
        const Color(0xFFFFC21A));
    _text(c, 'KIP     ${MoneyFormat.kip(usd * rates.appliedKip)}',
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 1 * 23.5, totalW - labelW - 16, 23.5),
        20, bold: true, right: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 2 * 23.5, totalW - labelW, 23.5),
        const Color(0xFF91D18B));
    _text(c, 'THB     ${MoneyFormat.thb(usd * rates.appliedThb)}',
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 2 * 23.5, totalW - labelW - 16, 23.5),
        20, bold: true, right: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 3 * 23.5, totalW - labelW, 23.5),
        const Color(0xFF23B6D8));
    _text(c, 'KRW     ${MoneyFormat.krw(usd * rates.appliedKrw)}',
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 3 * 23.5, totalW - labelW - 16, 23.5),
        20, bold: true, right: true);
    final payTop = sumTop + 204;
    const payGap = 4.0;
    final payW = (w - payGap * 3) / 4;
    final payRects = <Rect>[
      Rect.fromLTWH(0, payTop, payW, 150),
      Rect.fromLTWH(payW + payGap, payTop, payW, 150),
      Rect.fromLTWH((payW + payGap) * 2, payTop, payW, 150),
      Rect.fromLTWH((payW + payGap) * 3, payTop, payW, 150),
    ];

    for (final r in payRects) {
      _box(c, r, Colors.white);
    }

    _payment(
      c,
      qrUsd,
      'BCEL (USD):',
      '(SungHo Park)\n010-12-01-\n017655-60-001',
      payRects[0],
    );
    _payment(
      c,
      qrKip,
      'BCEL (KIP):',
      '(SungHo Park)\n013-12-00-\n017655-60-001',
      payRects[1],
    );
    _payment(
      c,
      qrThb,
      'BCEL (Baht):',
      '(SungHo Park)\n010-12-02-\n017655-60-001',
      payRects[2],
    );
    _text(
      c,
      '한국 원화 계좌:\n경남은행\n571-22-0330221\n박성호',
      payRects[3].deflate(8),
      22,
      bold: true,
      center: true,
      maxLines: 4,
      lineHeight: 1.35,
    );

    final noteTop = payTop + 150;
    _text(c, '', Rect.fromLTWH(15, noteTop, w - 30, 42), 1);

    final signTop = noteTop + 46;
    final signW = w * .26;
    final signH = 105.0;
    _box(c, Rect.fromLTWH(0, signTop, signW, signH), Colors.white);
    _box(c, Rect.fromLTWH(w - signW, signTop, signW, signH), Colors.white);
    _text(c, '엘케이 (LK)무역', Rect.fromLTWH(18, signTop + 14, signW - 36, 30),
        20, bold: true);
    _imageContain(c, stamp, Rect.fromLTWH(8, signTop + 4, signW - 16, signH - 8));
    _text(
      c,
      docText.footerText,
      Rect.fromLTWH(signW + 18, signTop + 6, w - signW * 2 - 36, signH - 12),
      docText.footerFontSize,
      center: true,
      maxLines: 6,
      lineHeight: 1.05,
    );
    _text(c, '고객사 확인', Rect.fromLTWH(w - signW + 18, signTop + 14, signW - 36, 30),
        18, bold: true);
  }

  void _payment(Canvas c, ui.Image image, String title, String detail, Rect r) {
    _imageContain(c, image, Rect.fromLTWH(r.left + 6, r.top + 6, 132, 132));
    _text(c, title, Rect.fromLTWH(r.left + 144, r.top + 8, r.width - 150, 32), 22, bold: true, center: true);
    _text(c, detail, Rect.fromLTWH(r.left + 144, r.top + 42, r.width - 150, 96),
        22, bold: true, center: true);
  }

  void _kv(Canvas c, String k, String v, Rect r) {
    const labelW = 165.0;
    _text(
      c,
      k,
      Rect.fromLTWH(r.left, r.top, labelW, r.height),
      16,
      bold: true,
      center: true,
    );
    _text(
      c,
      v,
      Rect.fromLTWH(r.left + labelW, r.top, r.width - labelW, r.height),
      19,
      bold: v != '-',
      center: true,
    );
  }

  void _labelValue(Canvas c, String label, String value, Rect r) {
    _box(c, r, paleBlue);
    _text(c, label, Rect.fromLTWH(r.left, r.top + 4, r.width, 22),
        14, bold: true, center: true);
    _text(c, value, Rect.fromLTWH(r.left, r.top + 26, r.width, r.height - 30),
        30, bold: true, center: true);
  }

  void _box(Canvas c, Rect r, Color fill) {
    c.drawRect(r, Paint()..color = fill);
    c.drawRect(
      r,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _imageContainTrimmed(
    Canvas c,
    ui.Image image,
    Rect box, {
    double trimRatio = .18,
  }) {
    final insetX = image.width * trimRatio;
    final insetY = image.height * trimRatio;
    final source = Rect.fromLTRB(
      insetX,
      insetY,
      image.width - insetX,
      image.height - insetY,
    );
    final ratio = source.width / source.height;
    var dw = box.width;
    var dh = dw / ratio;
    if (dh > box.height) {
      dh = box.height;
      dw = dh * ratio;
    }
    final dst = Rect.fromLTWH(
      box.left + (box.width - dw) / 2,
      box.top + (box.height - dh) / 2,
      dw,
      dh,
    );
    c.drawImageRect(image, source, dst, Paint());
  }
  void _imageContain(Canvas c, ui.Image image, Rect box) {
    final ratio = image.width / image.height;
    var dw = box.width;
    var dh = dw / ratio;
    if (dh > box.height) {
      dh = box.height;
      dw = dh * ratio;
    }
    final dst = Rect.fromLTWH(
      box.left + (box.width - dw) / 2,
      box.top + (box.height - dh) / 2,
      dw,
      dh,
    );
    _image(c, image, dst);
  }

  void _image(Canvas c, ui.Image image, Rect dst) {
    c.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _text(Canvas c, String text, Rect r, double size,
      {bool bold = false, bool center = false, bool right = false, int maxLines = 3, double lineHeight = 1.15}) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: ink,
          fontFamily: 'NotoSansKR',
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          height: lineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : (right ? TextAlign.right : TextAlign.left),
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: r.width);
    final y = r.top + (r.height - p.height).clamp(0, r.height) / 2;
    final x = center ? r.left + (r.width - p.width) / 2 : (right ? r.right - p.width : r.left);
    p.paint(c, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _DigitalQuotationPainter oldDelegate) => true;
}











