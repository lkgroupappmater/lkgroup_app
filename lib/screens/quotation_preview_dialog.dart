import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money_format.dart';
import '../core/route_catalog.dart';
import '../services/document_pdf_export.dart';
import '../services/exchange_rate_service.dart';
import '../services/quote_freight_calculator.dart';


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
  });

  final String routeLabel;
  final List<QuotationPreviewBox> boxes;
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;

  @override
  State<QuotationPreviewDialog> createState() => _QuotationPreviewDialogState();
}

class _QuotationPreviewDialogState extends State<QuotationPreviewDialog> {
  ui.Image? _logo;
  ui.Image? _qrUsd;
  ui.Image? _qrKip;
  ui.Image? _qrThb;
  bool _loading = true;
  bool _saving = false;
  late final DateTime _issuedAt;

  static const double _docWidth = 1540;
  int get _visibleRows => widget.boxes.length < 10 ? 10 : widget.boxes.length;
  double get _docHeight => 959 + (_visibleRows - 10) * 28;

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
      ]);
      if (!mounted) return;
      setState(() {
        _logo = assets[0];
        _qrUsd = assets[1];
        _qrKip = assets[2];
        _qrThb = assets[3];
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
        issuedAt: _issuedAt,
        logo: _logo!,
        qrUsd: _qrUsd!,
        qrKip: _qrKip!,
        qrThb: _qrThb!,
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
      final pdf = await DocumentPdfExport.quotation(png);
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
    final ready = !_loading && _logo != null;
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
                              final width =
                                  (constraints.maxWidth - 16).clamp(320.0, 900.0);
                              final height = width * _docHeight / _docWidth;
                              return InteractiveViewer(
                                minScale: .7,
                                maxScale: 4,
                                constrained: false,
                                boundaryMargin: const EdgeInsets.all(80),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
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
              padding: const EdgeInsets.all(8),
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
    required this.issuedAt,
    required this.logo,
    required this.qrUsd,
    required this.qrKip,
    required this.qrThb,
  });

  final String routeLabel;
  final List<QuotationPreviewBox> boxes;
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;
  final DateTime issuedAt;
  final ui.Image logo;
  final ui.Image qrUsd;
  final ui.Image qrKip;
  final ui.Image qrThb;

  static const ink = Color(0xFF182433);
  static const line = Color(0xFF8B97A3);
  static const paleBlue = Color(0xFFEAF3FA);
  static const actualColor = Color(0xFFFFF2CC);
  static const volumeColor = Color(0xFFE2F0D9);
  static const appliedColor = Color(0xFFD9EAF7);
  static const totalColor = Color(0xFFFFF49A);

  @override
  void paint(Canvas c, Size size) {
    final w = size.width;
    final h = size.height;
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _image(c, logo, Rect.fromLTWH(18, 12, 120, 68));
    _text(c, '${RouteCatalog.documentTitleFor(routeLabel)} 가견적서',
        Rect.fromLTWH(180, 16, 1000, 58), 39, bold: true, center: true);
    _labelValue(c, '구획(Zone)', '-', Rect.fromLTWH(w - 300, 8, 282, 72));

    final infoTop = 90.0;
    _box(c, Rect.fromLTWH(0, infoTop, w, 72), paleBlue.withOpacity(.38));
    _kv(c, '회사명', '엘케이(LK)무역', Rect.fromLTWH(8, infoTop + 4, w * .49, 28));
    _kv(c, '견적일',
        '${issuedAt.year}-${issuedAt.month.toString().padLeft(2, '0')}-${issuedAt.day.toString().padLeft(2, '0')}',
        Rect.fromLTWH(8, infoTop + 34, w * .49, 28));
    _kv(c, '고객명/회사명', '-', Rect.fromLTWH(w * .5, infoTop + 4, w * .49, 28));
    _kv(c, '연락처', '-', Rect.fromLTWH(w * .5, infoTop + 34, w * .49, 28));

    const tableTop = 170.0;
    const headerH = 36.0;
    const rowH = 28.0;
    final rowCount = boxes.length < 10 ? 10 : boxes.length;
    final cols = <double>[0, 65, 190, 280, 430, 580, 730, 875, 1040, 1230, 1540];
    final headers = <String>[
      'No.', '종류', '수량', '실제중량(kg)', '용적중량(kg)', '운임적용중량(kg)',
      '단가', '청구운임', '규격(cm)', '비고'
    ];
    final fills = <Color?>[
      null, null, null, actualColor, volumeColor, appliedColor, null, paleBlue, null, null
    ];

    for (var i = 0; i < headers.length; i++) {
      final r = Rect.fromLTRB(cols[i], tableTop, cols[i + 1], tableTop + headerH);
      _box(c, r, fills[i] ?? const Color(0xFFF6F7F9));
      _text(c, headers[i], r.deflate(3), 15, bold: true, center: true);
    }

    for (var i = 0; i < rowCount; i++) {
      final y = tableTop + headerH + i * rowH;
      final has = i < boxes.length;
      final b = has ? boxes[i] : null;
      final actualWins =
          b != null && b.result.actualWeightKg >= b.result.volumeWeightKg;
      final volumeWins =
          b != null && b.result.volumeWeightKg > b.result.actualWeightKg;

      for (var col = 0; col < headers.length; col++) {
        Color fill = Colors.white;
        if (has && col == 3 && actualWins) fill = actualColor;
        if (has && col == 4 && volumeWins) fill = volumeColor;
        if (has && col == 5) fill = appliedColor;
        _box(c, Rect.fromLTRB(cols[col], y, cols[col + 1], y + rowH), fill);
      }
      if (!has || b == null) continue;

      final values = <String>[
        '${i + 1}',
        '화물',
        '${b.quantity}',
        _fmtWeight(b.result.actualWeightKg),
        _fmtWeight(b.result.volumeWeightKg),
        _fmtWeight(b.result.chargeableWeightKg),
        '\$${b.result.ratePerKg.toStringAsFixed(2)}',
        MoneyFormat.usd(b.result.amountUsd),
        '${_fmtWeight(b.lengthCm)}×${_fmtWeight(b.widthCm)}×${_fmtWeight(b.heightCm)}',
        actualWins ? '실중량 적용' : '용적 적용',
      ];
      for (var col = 0; col < values.length; col++) {
        _text(c, values[col],
            Rect.fromLTRB(cols[col] + 3, y + 2, cols[col + 1] - 3, y + rowH - 2),
            col == 7 ? 14 : 13,
            bold: col == 5 || col == 7,
            center: true);
      }
    }

    final sumTop = tableTop + headerH + rowCount * rowH + 8;
    final leftW = w * .70;
    _box(c, Rect.fromLTWH(0, sumTop, leftW, 120), const Color(0xFFFBFCFD));
    _text(c, 'Remark/비고', Rect.fromLTWH(10, sumTop + 7, leftW - 20, 24),
        17, bold: true);
    _text(
      c,
      '본 가견적은 입력된 중량/규격을 기준으로 한 예상 운임입니다. '
      '실제 입고 후 실측 중량·용적중량 중 큰 값을 운임 적용중량으로 사용하며, '
      '최종 청구금액은 실제 측정 결과에 따라 달라질 수 있습니다.',
      Rect.fromLTWH(10, sumTop + 35, leftW - 20, 76),
      14,
    );

    final totalX = leftW + 6;
    final totalW = w - totalX;
    _box(c, Rect.fromLTWH(totalX, sumTop, totalW, 120), totalColor);
    _text(c, '가견적 총액', Rect.fromLTWH(totalX + 8, sumTop + 8, totalW - 16, 24),
        18, bold: true, center: true);
    final usd = result.totalUsd;
    final money = <String>[
      'USD  ${MoneyFormat.usd(usd)}',
      'KIP  ${MoneyFormat.kip(usd * rates.appliedKip)}',
      'THB  ${MoneyFormat.thb(usd * rates.appliedThb)}',
      'KRW  ${MoneyFormat.krw(usd * rates.appliedKrw)}',
    ];
    for (var i = 0; i < money.length; i++) {
      _text(c, money[i],
          Rect.fromLTWH(totalX + 15, sumTop + 34 + i * 20, totalW - 30, 20),
          17, bold: true, center: true);
    }

    final payTop = sumTop + 132;
    _payment(c, qrUsd, 'BCEL (USD)', '(SungHo Park)\n010-12-01-\n017655-60-001',
        Rect.fromLTWH(6, payTop, w * .31, 145));
    _payment(c, qrKip, 'BCEL (KIP)', '(SungHo Park)\n013-12-00-\n017655-60-001',
        Rect.fromLTWH(w * .335, payTop, w * .31, 145));
    _payment(c, qrThb, 'BCEL (Baht)', '(SungHo Park)\n010-12-02-\n017655-60-001',
        Rect.fromLTWH(w * .665, payTop, w * .31, 145));

    final noteTop = payTop + 150;
    _text(
      c,
      '* 운임은 USD 기준이며 표시된 기타 통화는 현재 앱 적용 환율 기준입니다.  '
      '* 실제 입고 후 중량/크기 실측 결과에 따라 최종 운임이 확정됩니다.',
      Rect.fromLTWH(15, noteTop, w - 30, 42),
      13,
      center: true,
    );

    final signTop = noteTop + 46;
    _box(c, Rect.fromLTWH(0, signTop, w * .48, h - signTop - 2), Colors.white);
    _box(c, Rect.fromLTWH(w * .52, signTop, w * .48, h - signTop - 2), Colors.white);
    _text(c, '엘케이 (LK)무역', Rect.fromLTWH(18, signTop + 14, w * .42, 30),
        18, bold: true);
    _text(c, '고객사 확인', Rect.fromLTWH(w * .54, signTop + 14, w * .42, 30),
        18, bold: true);
  }

  void _payment(Canvas c, ui.Image image, String title, String detail, Rect r) {
    _image(c, image, Rect.fromLTWH(r.left + 4, r.top + 2, 128, 128));
    _text(c, title, Rect.fromLTWH(r.left + 140, r.top + 10, r.width - 145, 28),
        19, bold: true);
    _text(c, detail, Rect.fromLTWH(r.left + 140, r.top + 38, r.width - 145, 92),
        16, bold: true);
  }

  void _kv(Canvas c, String k, String v, Rect r) {
    _text(c, '$k  ', Rect.fromLTWH(r.left, r.top, 145, r.height), 15, bold: true);
    _text(c, v, Rect.fromLTWH(r.left + 145, r.top, r.width - 145, r.height),
        17, bold: v != '-');
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

  void _image(Canvas c, ui.Image image, Rect dst) {
    c.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _text(Canvas c, String text, Rect r, double size,
      {bool bold = false, bool center = false}) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: ink,
          fontFamily: 'NotoSansKR',
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: r.width);
    final y = r.top + (r.height - p.height).clamp(0, r.height) / 2;
    final x = center ? r.left + (r.width - p.width) / 2 : r.left;
    p.paint(c, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _DigitalQuotationPainter oldDelegate) => true;
}
