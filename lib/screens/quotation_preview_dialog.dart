import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  final GlobalKey _captureKey = GlobalKey();
  final TransformationController _transform = TransformationController();

  ui.Image? _templateImage;
  bool _loading = true;
  bool _saving = false;
  late final DateTime _issuedAt;

  String get _routeKey => RouteCatalog.keyFor(widget.routeLabel);
  bool get _isKrLaSea => _routeKey == 'kr_la_sea';

  @override
  void initState() {
    super.initState();
    _issuedAt = DateTime.now();
    _loadTemplate();
  }

  @override
  void dispose() {
    _transform.dispose();
    _templateImage?.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    try {
      final path = _isKrLaSea
          ? 'assets/quotation_forms/kr_la_sea.png'
          : 'assets/quotation_forms/${_routeKey.toLowerCase()}.png';
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

  String _two(int v) => v.toString().padLeft(2, '0');

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.45, 5.0);
    _transform.value = Matrix4.identity()..scale(target);
  }

  void _resetZoom() {
    _transform.value = Matrix4.identity();
  }

  Future<void> _savePng() async {
    setState(() => _saving = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('견적서 이미지를 생성하지 못했습니다.');

      // 원본 폼이 이미 2292px 폭입니다. 1.5배로 저장하여 프린트 여유 해상도를 확보합니다.
      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('PNG 변환에 실패했습니다.');
      final Uint8List bytes = byteData.buffer.asUint8List();

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
            uri == null ? '이미지 저장을 취소했습니다.' : '데이터가 반영된 견적서 이미지를 저장했습니다.',
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
                    tooltip: '축소',
                    onPressed: () => _zoom(0.8),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  IconButton(
                    tooltip: '원래 크기',
                    onPressed: _resetZoom,
                    icon: const Icon(Icons.fit_screen_outlined),
                  ),
                  IconButton(
                    tooltip: '확대',
                    onPressed: () => _zoom(1.25),
                    icon: const Icon(Icons.add_circle_outline),
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
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final surface = _buildSurface(image);
                              return InteractiveViewer(
                                transformationController: _transform,
                                panEnabled: true,
                                scaleEnabled: true,
                                minScale: 0.45,
                                maxScale: 5.0,
                                boundaryMargin: const EdgeInsets.all(300),
                                clipBehavior: Clip.none,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  child: Center(child: surface),
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
                      label: const Text('데이터 반영 이미지 저장'),
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

  Widget _buildSurface(ui.Image image) {
    // 1차 완성형 검증 노선: 한국 -> 라오스 해상.
    if (_isKrLaSea) {
      final detailRows = widget.boxes.length > 10 ? widget.boxes.length + 1 : 10;
      final extraRows = detailRows - 10;
      final height = 1526.0 + (extraRows * 32.0);

      return RepaintBoundary(
        key: _captureKey,
        child: CustomPaint(
          size: Size(2292, height),
          painter: _KrLaSeaQuotationPainter(
            template: image,
            boxes: widget.boxes,
            result: widget.result,
            rates: widget.rates,
            issuedAt: _issuedAt,
            detailRows: detailRows,
          ),
        ),
      );
    }

    // 다른 노선은 다음 확장 단계 전까지 기존 실제 Excel 폼 이미지만 유지.
    return RepaintBoundary(
      key: _captureKey,
      child: RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _KrLaSeaQuotationPainter extends CustomPainter {
  const _KrLaSeaQuotationPainter({
    required this.template,
    required this.boxes,
    required this.result,
    required this.rates,
    required this.issuedAt,
    required this.detailRows,
  });

  final ui.Image template;
  final List<QuotationPreviewBox> boxes;
  final QuoteFreightResult result;
  final ExchangeRateSettings rates;
  final DateTime issuedAt;
  final int detailRows;

  static const double sourceWidth = 2292;
  static const double sourceHeight = 1526;

  // 실제 Excel 연결 그림에서 측정한 상세 행 영역.
  static const double bodyTop = 293;
  static const double originalBodyBottom = 613;
  static const double rowHeight = 32;

  static const List<double> xs = <double>[
    24, 159, 362, 426, 519, 698, 942, 1023, 1104, 1185,
    1372, 1620, 1856, 2045, 2267,
  ];

  double get extraHeight => (detailRows - 10) * rowHeight;
  double yShift(double sourceY) =>
      sourceY >= originalBodyBottom ? sourceY + extraHeight : sourceY;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.high;

    if (extraHeight <= 0) {
      canvas.drawImageRect(
        template,
        Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
        Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
        paint,
      );
    } else {
      // 상단: 기존 상세 10행 마지막까지 그대로.
      canvas.drawImageRect(
        template,
        const Rect.fromLTWH(0, 0, sourceWidth, originalBodyBottom),
        const Rect.fromLTWH(0, 0, sourceWidth, originalBodyBottom),
        paint,
      );

      // 추가 행: 원본 폼과 동일한 흰 배경 + 셀 경계선.
      final extraRect = Rect.fromLTWH(
        24,
        originalBodyBottom,
        2267 - 24,
        extraHeight,
      );
      canvas.drawRect(extraRect, Paint()..color = Colors.white);

      final linePaint = Paint()
        ..color = const Color(0xFF5F6368)
        ..strokeWidth = 1;
      for (final x in xs) {
        canvas.drawLine(
          Offset(x, originalBodyBottom),
          Offset(x, originalBodyBottom + extraHeight),
          linePaint,
        );
      }
      for (var i = 0; i <= detailRows - 10; i++) {
        final y = originalBodyBottom + (i * rowHeight);
        canvas.drawLine(Offset(24, y), Offset(2267, y), linePaint);
      }

      // 하단(합계/Remark/QR/서명 등)을 추가된 행만큼 아래로 이동.
      canvas.drawImageRect(
        template,
        const Rect.fromLTWH(
          0,
          originalBodyBottom,
          sourceWidth,
          sourceHeight - originalBodyBottom,
        ),
        Rect.fromLTWH(
          0,
          originalBodyBottom + extraHeight,
          sourceWidth,
          sourceHeight - originalBodyBottom,
        ),
        paint,
      );
    }

    _paintDate(canvas);
    _paintDetailRows(canvas);
    _paintTotals(canvas);
  }

  void _paintDate(Canvas canvas) {
    _clearInterior(canvas, const Rect.fromLTRB(520, 154, 1102, 187));
    _text(
      canvas,
      _date(issuedAt),
      const Rect.fromLTRB(520, 154, 1102, 187),
      fontSize: 19,
      bold: true,
    );
  }

  void _paintDetailRows(Canvas canvas) {
    final minimum = 1.5;

    for (var i = 0; i < detailRows; i++) {
      final top = bodyTop + (i * rowHeight);
      final bottom = top + rowHeight;

      // 기존 샘플 값/수식 캐시를 모두 지우고 현재 데이터 기준으로 다시 표시.
      for (var col = 0; col < xs.length - 1; col++) {
        _clearInterior(
          canvas,
          Rect.fromLTRB(xs[col], top, xs[col + 1], bottom),
        );
      }

      _text(
        canvas,
        '${i + 1}',
        Rect.fromLTRB(xs[0], top, xs[1], bottom),
        fontSize: 17,
        bold: true,
      );

      if (i >= boxes.length) continue;
      final b = boxes[i];
      final line = b.result;
      final rate = line.ratePerKg;

      final actualAmount = _minimumCharge(line.actualWeightKg * rate, minimum);
      final volumeAmount = _minimumCharge(line.volumeWeightKg * rate, minimum);

      final values = <String>[
        'BOX',
        _num(rate),
        '${b.quantity}',
        _num(b.weightKg),
        _num(line.actualWeightKg),
        _num(b.lengthCm),
        _num(b.widthCm),
        _num(b.heightCm),
        _num(line.volumeWeightKg / (b.quantity < 1 ? 1 : b.quantity)),
        _num(line.volumeWeightKg),
        _num(actualAmount),
        _num(volumeAmount),
        _num(line.amountUsd),
      ];

      // No. 이후 13개 표시 컬럼.
      for (var col = 1; col < xs.length - 1; col++) {
        _text(
          canvas,
          values[col - 1],
          Rect.fromLTRB(xs[col], top, xs[col + 1], bottom),
          fontSize: 15,
          bold: col >= 11,
        );
      }
    }
  }

  void _paintTotals(Canvas canvas) {
    final shift = extraHeight;
    final totalTop = 613 + shift;
    final totalBottom = 645 + shift;

    // 합계행의 기존 샘플 값을 제거.
    for (var col = 0; col < xs.length - 1; col++) {
      _clearInterior(
        canvas,
        Rect.fromLTRB(xs[col], totalTop, xs[col + 1], totalBottom),
      );
    }

    // 합계 라벨은 A:B를 합친 것처럼 보이도록 중앙 표시.
    _text(
      canvas,
      '합 계',
      Rect.fromLTRB(24, totalTop, 362, totalBottom),
      fontSize: 17,
      bold: true,
    );

    final totalQty = boxes.fold<int>(0, (s, b) => s + b.quantity);
    final totalActual =
        boxes.fold<double>(0, (s, b) => s + b.result.actualWeightKg);
    final totalVolume =
        boxes.fold<double>(0, (s, b) => s + b.result.volumeWeightKg);

    _text(
      canvas,
      '$totalQty',
      Rect.fromLTRB(426, totalTop, 519, totalBottom),
      fontSize: 17,
      bold: true,
    );
    _text(
      canvas,
      _num(totalActual),
      Rect.fromLTRB(698, totalTop, 942, totalBottom),
      fontSize: 17,
      bold: true,
    );
    _text(
      canvas,
      _num(totalVolume),
      Rect.fromLTRB(1372, totalTop, 1620, totalBottom),
      fontSize: 17,
      bold: true,
    );

    // 우측 운임 합계 / 할인 / 특별할인 / VAT.
    _replaceAmountCell(canvas, 645 + shift, 687 + shift, '\$ ${_money(result.totalUsd, 2)}');
    _replaceAmountCell(canvas, 687 + shift, 729 + shift, '\$ -');
    _replaceAmountCell(canvas, 729 + shift, 771 + shift, '\$ -');
    _replaceAmountCell(canvas, 771 + shift, 813 + shift, '\$ -');

    final kip = result.totalUsd * rates.appliedKip;
    final thb = result.totalUsd * rates.appliedThb;
    final krw = result.totalUsd * rates.appliedKrw;

    _replaceAmountCell(canvas, 813 + shift, 855 + shift, '\$ ${_money(result.totalUsd, 2)}',
        color: const Color(0xFF0070C0));
    _replaceAmountCell(canvas, 855 + shift, 897 + shift, '₭ ${_money(kip, 0)}',
        color: const Color(0xFF0070C0));
    _replaceAmountCell(canvas, 897 + shift, 939 + shift, '฿ ${_money(thb, 0)}',
        color: const Color(0xFF0070C0));
    _replaceAmountCell(canvas, 939 + shift, 981 + shift, '₩ ${_money(krw, 0)}',
        color: const Color(0xFF0070C0));
  }

  void _replaceAmountCell(
    Canvas canvas,
    double top,
    double bottom,
    String value, {
    Color color = Colors.black,
  }) {
    const left = 2045.0;
    const right = 2267.0;
    _clearInterior(canvas, Rect.fromLTRB(left, top, right, bottom));
    _text(
      canvas,
      value,
      Rect.fromLTRB(left, top, right, bottom),
      fontSize: 18,
      bold: true,
      color: color,
      align: TextAlign.right,
      paddingRight: 14,
    );
  }

  double _minimumCharge(double amount, double minimum) {
    if (amount <= 0) return 0;
    return amount < minimum ? minimum : amount;
  }

  void _clearInterior(Canvas canvas, Rect rect) {
    final inner = Rect.fromLTRB(
      rect.left + 1.5,
      rect.top + 1.5,
      rect.right - 1.5,
      rect.bottom - 1.5,
    );
    canvas.drawRect(inner, Paint()..color = Colors.white);
  }

  void _text(
    Canvas canvas,
    String value,
    Rect rect, {
    double fontSize = 15,
    bool bold = false,
    Color color = Colors.black,
    TextAlign align = TextAlign.center,
    double paddingRight = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout(maxWidth: rect.width - paddingRight - 4);

    double dx;
    if (align == TextAlign.right) {
      dx = rect.right - painter.width - paddingRight;
    } else if (align == TextAlign.left) {
      dx = rect.left + 4;
    } else {
      dx = rect.left + (rect.width - painter.width) / 2;
    }
    final dy = rect.top + (rect.height - painter.height) / 2;
    painter.paint(canvas, Offset(dx, dy));
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
  bool shouldRepaint(covariant _KrLaSeaQuotationPainter oldDelegate) {
    return oldDelegate.template != template ||
        oldDelegate.boxes != boxes ||
        oldDelegate.result != result ||
        oldDelegate.rates != rates ||
        oldDelegate.detailRows != detailRows ||
        oldDelegate.issuedAt != issuedAt;
  }
}
