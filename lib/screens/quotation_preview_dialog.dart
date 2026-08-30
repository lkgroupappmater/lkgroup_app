import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/route_catalog.dart';
import '../services/exchange_rate_service.dart';
import '../services/quote_freight_calculator.dart';

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
  ui.Image? _templateImage;
  bool _loading = true;
  bool _saving = false;
  late final DateTime _issuedAt;

  String get _formRouteKey => RouteCatalog.formRouteKeyFor(widget.routeLabel);
  _RouteFormConfig get _config => _RouteFormConfig.forKey(_formRouteKey);

  @override
  void initState() {
    super.initState();
    _issuedAt = DateTime.now();
    _loadTemplate();
  }

  @override
  void dispose() {
    _templateImage?.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    try {
      final path = 'assets/quotation_forms/${_formRouteKey.toLowerCase()}.png';
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _templateImage = frame.image;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('견적서 원본 폼 로딩 실패: $error')),
      );
    }
  }

  int get _detailRows {
    final base = _config.baseRows;
    return widget.boxes.length > base ? widget.boxes.length + 1 : base;
  }

  Size _logicalSize(ui.Image image) {
    final extra = (_detailRows - _config.baseRows) * _config.rowHeight;
    return Size(image.width.toDouble(), image.height.toDouble() + extra);
  }

  Rect _documentRect(ui.Image image) {
    final logical = _logicalSize(image);
    // 기존 Excel 연결 그림의 바깥쪽 캡처 여백만 제거합니다.
    // 문서 내부 셀/QR/도장/Remark 영역은 건드리지 않습니다.
    final x = image.width * .0105;
    final y = image.height * .0157;
    return Rect.fromLTRB(x, y, logical.width - x, logical.height - y);
  }
  Widget _preview(ui.Image image) {
    final logical = _logicalSize(image);
    final doc = _documentRect(image);
    final screenWidth = MediaQuery.sizeOf(context).width - 28;
    final previewWidth = screenWidth.clamp(320.0, 760.0);
    final previewHeight = previewWidth * doc.height / doc.width;

    return SizedBox(
      width: previewWidth,
      height: previewHeight,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: doc.width,
          height: doc.height,
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(-doc.left, -doc.top),
              child: SizedBox(
                width: logical.width,
                height: logical.height,
                child: CustomPaint(
                  painter: _QuotationFormPainter(
                    routeLabel: widget.routeLabel,
                    template: image,
                    boxes: widget.boxes,
                    result: widget.result,
                    rates: widget.rates,
                    issuedAt: _issuedAt,
                    config: _config,
                    detailRows: _detailRows,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  Future<Uint8List> _renderHighResolutionPng() async {
    final image = _templateImage;
    if (image == null) throw StateError('견적서 원본 폼을 불러오지 못했습니다.');

    final logical = _logicalSize(image);
    final doc = _documentRect(image);
    const exportScale = 1.75;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(exportScale, exportScale)
      ..translate(-doc.left, -doc.top);

    _QuotationFormPainter(
      routeLabel: widget.routeLabel,
      template: image,
      boxes: widget.boxes,
      result: widget.result,
      rates: widget.rates,
      issuedAt: _issuedAt,
      config: _config,
      detailRows: _detailRows,
    ).paint(canvas, logical);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      (doc.width * exportScale).round(),
      (doc.height * exportScale).round(),
    );
    picture.dispose();

    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    if (byteData == null) throw StateError('PNG 변환에 실패했습니다.');
    return byteData.buffer.asUint8List();
  }
  String _two(int v) => v.toString().padLeft(2, '0');

  Future<void> _savePng() async {
    setState(() => _saving = true);
    try {
      final bytes = await _renderHighResolutionPng();
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final fileName =
          '${prefix.isEmpty ? 'QUOTATION' : prefix}_QUOTATION_${_issuedAt.year}${_two(_issuedAt.month)}${_two(_issuedAt.day)}.png';

      final uri = await FilePicker.saveFile(
        dialogTitle: '견적서 이미지 저장 위치 선택',
        fileName: fileName,
        bytes: bytes,
        mimeType: 'image/png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri == null ? '이미지 저장을 취소했습니다.' : '고화질 견적서 이미지를 저장했습니다.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('견적서 이미지 저장 실패: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _templateImage;
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
                      '${widget.routeLabel} · 견적서 보기',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
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
                    : image == null
                        ? const Center(
                            child: Text(
                              '견적서 폼을 불러오지 못했습니다.',
                              style: TextStyle(color: Colors.white),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: Center(child: _preview(image)),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: image == null || _saving ? null : _savePng,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      label: const Text('고화질 이미지 저장'),
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

class _RouteFormConfig {
  const _RouteFormConfig({
    required this.key,
    required this.baseRows,
    required this.bodyTop,
    required this.bodyBottom,
    required this.totalTop,
    required this.amountStartTop,
    this.dateRect = const Rect.fromLTRB(520, 154, 1102, 187),
  });

  final String key;
  final int baseRows;
  final double bodyTop;
  final double bodyBottom;
  final double totalTop;
  final double amountStartTop;
  final Rect dateRect;

  double get rowHeight => (bodyBottom - bodyTop) / baseRows;

  static _RouteFormConfig forKey(String key) {
    // 실제 각 노선 Quotation 연결 그림을 기준으로 잡은 표 영역.
    switch (key) {
      case 'kr_la_sea':
        return const _RouteFormConfig(
          key: 'kr_la_sea',
          baseRows: 10,
          bodyTop: 293,
          bodyBottom: 613,
          totalTop: 613,
          amountStartTop: 645,
        );
      case 'kr_la_air':
        return const _RouteFormConfig(
          key: 'kr_la_air',
          baseRows: 10,
          bodyTop: 288,
          bodyBottom: 608,
          totalTop: 608,
          amountStartTop: 640,
        );
      case 'la_kr_air_exp':
        return const _RouteFormConfig(
          key: 'la_kr_air_exp',
          baseRows: 5,
          bodyTop: 245,
          bodyBottom: 405,
          totalTop: 405,
          amountStartTop: 437,
          dateRect: Rect.fromLTRB(530, 112, 1095, 145),
        );
      case 'la_th_land':
        return const _RouteFormConfig(
          key: 'la_th_land',
          baseRows: 5,
          bodyTop: 245,
          bodyBottom: 405,
          totalTop: 405,
          amountStartTop: 437,
          dateRect: Rect.fromLTRB(530, 112, 1095, 145),
        );
      case 'th_la_land':
        return const _RouteFormConfig(
          key: 'th_la_land',
          baseRows: 5,
          bodyTop: 250,
          bodyBottom: 410,
          totalTop: 410,
          amountStartTop: 442,
          dateRect: Rect.fromLTRB(530, 115, 1095, 148),
        );
      case 'la_vn_land':
      case 'vn_la_land':
        return _RouteFormConfig(
          key: key,
          baseRows: 5,
          bodyTop: 245,
          bodyBottom: 405,
          totalTop: 405,
          amountStartTop: 437,
          dateRect: const Rect.fromLTRB(530, 112, 1095, 145),
        );
      case 'la_ch_land':
        return const _RouteFormConfig(
          key: 'la_ch_land',
          baseRows: 5,
          bodyTop: 245,
          bodyBottom: 405,
          totalTop: 405,
          amountStartTop: 437,
          dateRect: Rect.fromLTRB(530, 112, 1095, 145),
        );
      case 'ch_la_land':
        return const _RouteFormConfig(
          key: 'ch_la_land',
          baseRows: 5,
          bodyTop: 255,
          bodyBottom: 415,
          totalTop: 415,
          amountStartTop: 447,
          dateRect: Rect.fromLTRB(530, 120, 1095, 153),
        );
      case 'la_kh_land':
      case 'kh_la_land':
        return _RouteFormConfig(
          key: key,
          baseRows: 5,
          bodyTop: 245,
          bodyBottom: 405,
          totalTop: 405,
          amountStartTop: 437,
          dateRect: const Rect.fromLTRB(530, 112, 1095, 145),
        );
      default:
        return _RouteFormConfig(
          key: key,
          baseRows: 5,
          bodyTop: 245,
          bodyBottom: 405,
          totalTop: 405,
          amountStartTop: 437,
        );
    }
  }
}

class _QuotationFormPainter extends CustomPainter {
  const _QuotationFormPainter({
    required this.routeLabel,
    required this.template,
    required this.boxes,
    required this.result,
    required this.rates,
    required this.issuedAt,
    required this.config,
    required this.detailRows,
  });

  final String routeLabel;
  final ui.Image template;
  final List<QuotationPreviewBox> boxes;
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;
  final DateTime issuedAt;
  final _RouteFormConfig config;
  final int detailRows;

  static const List<double> xRatio = <double>[
    0.0105, 0.0694, 0.1580, 0.1859, 0.2264, 0.3045, 0.4110,
    0.4464, 0.4817, 0.5170, 0.5986, 0.7068, 0.8098, 0.8922, 0.9891,
  ];

  double get _w => template.width.toDouble();
  double get _extraHeight => (detailRows - config.baseRows) * config.rowHeight;

  List<double> get xs => xRatio.map((v) => v * _w).toList(growable: false);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.high;
    final originalH = template.height.toDouble();

    if (_extraHeight <= 0) {
      canvas.drawImage(template, Offset.zero, paint);
    } else {
      canvas.drawImageRect(
        template,
        Rect.fromLTWH(0, 0, _w, config.bodyBottom),
        Rect.fromLTWH(0, 0, _w, config.bodyBottom),
        paint,
      );

      // 추가 행은 원본 Excel 폼의 마지막 빈 상세행을 그대로 반복 복사.
      final rowH = config.rowHeight;
      final left = xs.first;
      final right = xs.last;
      final sourceBlankRow = Rect.fromLTRB(
        left,
        config.bodyBottom - rowH,
        right,
        config.bodyBottom,
      );
      for (var i = 0; i < detailRows - config.baseRows; i++) {
        final top = config.bodyBottom + (i * rowH);
        canvas.drawImageRect(
          template,
          sourceBlankRow,
          Rect.fromLTRB(left, top, right, top + rowH),
          paint,
        );
      }

      // 합계 / Remark / QR / 송금 / 도장 / 서명 영역은 원래 크기 그대로 아래로 이동.
      canvas.drawImageRect(
        template,
        Rect.fromLTWH(0, config.bodyBottom, _w, originalH - config.bodyBottom),
        Rect.fromLTWH(
          0,
          config.bodyBottom + _extraHeight,
          _w,
          originalH - config.bodyBottom,
        ),
        paint,
      );
    }

    _paintRouteHeader(canvas);
    _paintDate(canvas);
    _paintRows(canvas);
    _paintTotals(canvas);
  }

  void _paintRouteHeader(Canvas canvas) {
    // BASE는 레이아웃만 사용하고 문서용 타이틀은 DB document_title 기준으로 표시.
    final h = template.height.toDouble();
    final documentTitle = RouteCatalog.documentTitleFor(routeLabel);
    final titleRect = Rect.fromLTRB(_w * .19, h * .018, _w * .81, h * .108);
    _clear(canvas, titleRect);
    _text(
      canvas,
      '$documentTitle xxth 견적서',
      titleRect,
      48,
      bold: true,
    );

    final receipt = RouteCatalog.receiptExampleFor(routeLabel);
    if (receipt.isNotEmpty) {
      final receiptRect =
          Rect.fromLTRB(_w * .855, h * .09, _w * .985, h * .145);
      _clear(canvas, receiptRect);
      _text(canvas, receipt, receiptRect, 18, bold: true);
    }
  }

  void _paintDate(Canvas canvas) {
    final r = config.dateRect;
    _clear(canvas, r);
    _text(canvas, _date(issuedAt), r, 18, bold: true);
  }

  void _paintRows(Canvas canvas) {
    final xx = xs;
    final rowH = config.rowHeight;
    for (var i = 0; i < detailRows; i++) {
      final top = config.bodyTop + (i * rowH);
      final bottom = top + rowH;

      for (var c = 0; c < xx.length - 1; c++) {
        _clear(canvas, Rect.fromLTRB(xx[c], top, xx[c + 1], bottom));
      }

      _text(
        canvas,
        '${i + 1}',
        Rect.fromLTRB(xx[0], top, xx[1], bottom),
        20,
        bold: true,
      );

      if (i >= boxes.length) continue;
      final b = boxes[i];
      final line = b.result;
      final qty = b.quantity < 1 ? 1 : b.quantity;
      final unitVol = line.volumeWeightKg / qty;
      final minimum = line.ratePerKg;
      final actualFee = _minCharge(line.actualWeightKg * line.ratePerKg, minimum);
      final volumeFee = _minCharge(line.volumeWeightKg * line.ratePerKg, minimum);

      final values = <String>[
        'BOX',
        _num(line.ratePerKg),
        '$qty',
        _num(b.weightKg),
        _num(line.actualWeightKg),
        _num(b.lengthCm),
        _num(b.widthCm),
        _num(b.heightCm),
        _num(unitVol),
        _num(line.volumeWeightKg),
        _num(actualFee),
        _num(volumeFee),
        _num(line.amountUsd),
      ];

      for (var c = 1; c < xx.length - 1; c++) {
        _text(
          canvas,
          values[c - 1],
          Rect.fromLTRB(xx[c], top, xx[c + 1], bottom),
          c >= 11 ? 20 : 18,
          bold: c >= 11,
        );
      }
    }
  }

  void _paintTotals(Canvas canvas) {
    final xx = xs;
    final top = config.totalTop + _extraHeight;
    final bottom = top + config.rowHeight;

    for (var c = 0; c < xx.length - 1; c++) {
      _clear(canvas, Rect.fromLTRB(xx[c], top, xx[c + 1], bottom));
    }

    _text(
      canvas,
      '합 계',
      Rect.fromLTRB(xx[0], top, xx[2], bottom),
      15,
      bold: true,
    );

    final qty = boxes.fold<int>(0, (s, b) => s + b.quantity);
    final actual = boxes.fold<double>(0, (s, b) => s + b.result.actualWeightKg);
    final volume = boxes.fold<double>(0, (s, b) => s + b.result.volumeWeightKg);

    _text(canvas, '$qty', Rect.fromLTRB(xx[3], top, xx[4], bottom), 19, bold: true);
    _text(canvas, _num(actual), Rect.fromLTRB(xx[5], top, xx[6], bottom), 19, bold: true);
    _text(canvas, _num(volume), Rect.fromLTRB(xx[10], top, xx[11], bottom), 19, bold: true);

    final amountTop = config.amountStartTop + _extraHeight;
    final amountH = 42.0;
    _amount(canvas, amountTop, amountTop + amountH, '\$ ${_money(result.totalUsd, 2)}');
    _amount(canvas, amountTop + amountH, amountTop + amountH * 2, '\$ -');
    _amount(canvas, amountTop + amountH * 2, amountTop + amountH * 3, '\$ -');
    _amount(canvas, amountTop + amountH * 3, amountTop + amountH * 4, '\$ -');

    final kip = result.totalUsd * rates.appliedKip;
    final thb = result.totalUsd * rates.appliedThb;
    final krw = result.totalUsd * rates.appliedKrw;

    _amount(
      canvas,
      amountTop + amountH * 4,
      amountTop + amountH * 5,
      '\$ ${_money(result.totalUsd, 2)}',
      color: const Color(0xFF0070C0),
    );
    _amount(
      canvas,
      amountTop + amountH * 5,
      amountTop + amountH * 6,
      '₭ ${_money(kip, 0)}',
      color: const Color(0xFF0070C0),
    );
    _amount(
      canvas,
      amountTop + amountH * 6,
      amountTop + amountH * 7,
      '฿ ${_money(thb, 0)}',
      color: const Color(0xFF0070C0),
    );
    _amount(
      canvas,
      amountTop + amountH * 7,
      amountTop + amountH * 8,
      '₩ ${_money(krw, 0)}',
      color: const Color(0xFF0070C0),
    );
  }

  void _amount(Canvas canvas, double top, double bottom, String value,
      {Color color = Colors.black}) {
    final left = _w * 0.8922;
    final right = _w * 0.9891;
    final rect = Rect.fromLTRB(left, top, right, bottom);
    _clear(canvas, rect);
    _text(
      canvas,
      value,
      rect,
      20,
      bold: true,
      color: color,
      align: TextAlign.right,
      rightPadding: 12,
    );
  }

  double _minCharge(double amount, double minimum) {
    if (amount <= 0) return 0;
    return amount < minimum ? minimum : amount;
  }

  void _clear(Canvas canvas, Rect rect) {
    canvas.drawRect(
      Rect.fromLTRB(
        rect.left + 1.2,
        rect.top + 1.2,
        rect.right - 1.2,
        rect.bottom - 1.2,
      ),
      Paint()..color = Colors.white,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Rect rect,
    double fontSize, {
    bool bold = false,
    Color color = Colors.black,
    TextAlign align = TextAlign.center,
    double rightPadding = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: fontSize,
          height: 1,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout(maxWidth: rect.width - rightPadding - 4);

    final dx = align == TextAlign.right
        ? rect.right - tp.width - rightPadding
        : rect.left + (rect.width - tp.width) / 2;
    final dy = rect.top + (rect.height - tp.height) / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _num(num value) {
    final d = value.toDouble();
    if (d == d.roundToDouble()) return d.toStringAsFixed(0);
    if ((d * 10).roundToDouble() == d * 10) return d.toStringAsFixed(1);
    return d.toStringAsFixed(2);
  }

  String _money(double value, int decimals) {
    final fixed = value.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final raw = parts.first;
    final negative = raw.startsWith('-');
    final digits = negative ? raw.substring(1) : raw;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    final prefix = negative ? '-' : '';
    if (decimals == 0) return '$prefix$buffer';
    return '$prefix$buffer.${parts[1]}';
  }

  @override
  bool shouldRepaint(covariant _QuotationFormPainter oldDelegate) => true;
}



