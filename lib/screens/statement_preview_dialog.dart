import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/route_catalog.dart';
import '../core/money_format.dart';
import '../services/freight_service.dart';
import '../services/statement_service.dart';
import '../services/document_pdf_export.dart';

class StatementPreviewDialog extends StatefulWidget {
  const StatementPreviewDialog({
    super.key,
    required this.routeLabel,
    required this.year,
    required this.voyage,
    required this.receiptNumber,
  });

  final String routeLabel;
  final int year;
  final String voyage;
  final String receiptNumber;

  @override
  State<StatementPreviewDialog> createState() => _StatementPreviewDialogState();
}

class _StatementPreviewDialogState extends State<StatementPreviewDialog> {
  ui.Image? _template;
  List<Map<String, dynamic>> _rows = const [];
  FreightCalculation? _freight;
  String? _arrivalDate;
  bool _loading = true;
  bool _saving = false;

  String get _formRouteKey =>
      RouteCatalog.formRouteKeyFor(widget.routeLabel).toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _template?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data =
          await rootBundle.load('assets/statement_forms/$_formRouteKey.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();

      final rows = await StatementService.instance.rowsForReceipt(
        route: widget.routeLabel,
        year: widget.year,
        voyage: widget.voyage,
        receiptNumber: widget.receiptNumber,
      );
      if (rows.isEmpty) throw StateError('명세서에 표시할 화물 데이터가 없습니다.');

      final freight = await FreightService.instance.calculate(rows);
      final arrival = await StatementService.instance.arrivalDate(
        route: widget.routeLabel,
        year: widget.year,
        voyage: widget.voyage,
      );

      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _template = frame.image;
        _rows = rows;
        _freight = freight;
        _arrivalDate = arrival;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('명세서 로딩 실패: $error')),
      );
    }
  }

  int get _baseRows =>
      _formRouteKey == 'kr_la_sea' || _formRouteKey == 'kr_la_air' ? 10 : 5;
  int get _detailRows => _rows.length > _baseRows ? _rows.length + 1 : _baseRows;

  double _cropRatio() => 0.0;
  Size _logicalSize(ui.Image image) {
    final visibleHeight = image.height * (1 - _cropRatio());
    final rowHeight = visibleHeight * .028;
    final extra = (_detailRows - _baseRows) * rowHeight;
    return Size(image.width.toDouble(), visibleHeight + extra);
  }

  Rect _documentRect(ui.Image image) {
    final logical = _logicalSize(image);
    return Rect.fromLTWH(0, 0, logical.width, logical.height);
  }
  _StatementPainter _painter(ui.Image image) => _StatementPainter(
        template: image,
        routeLabel: widget.routeLabel,
        rows: _rows,
        freight: _freight!,
        receiptNumber: widget.receiptNumber,
        arrivalDate: _arrivalDate,
        baseRows: _baseRows,
        detailRows: _detailRows,
        sourceTop: image.height * _cropRatio(),
      );

  Future<Uint8List> _renderPng() async {
    final image = _template;
    if (image == null || _freight == null) {
      throw StateError('명세서를 아직 불러오지 못했습니다.');
    }
    final logical = _logicalSize(image);
    final doc = _documentRect(image);
    const scale = 1.75;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale, scale)
      ..translate(-doc.left, -doc.top);

    _painter(image).paint(canvas, logical);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      (doc.width * scale).round(),
      (doc.height * scale).round(),
    );
    picture.dispose();
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    if (bytes == null) throw StateError('PNG 변환에 실패했습니다.');
    return bytes.buffer.asUint8List();
  }
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await _renderPng();
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final safeReceipt = widget.receiptNumber.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]+'),
        '_',
      );
      final saved = await FilePicker.saveFile(
        dialogTitle: '명세서 이미지 저장 위치 선택',
        fileName:
            '${prefix.isEmpty ? 'STATEMENT' : prefix}_STATEMENT_$safeReceipt.png',
        bytes: bytes,
        mimeType: 'image/png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null ? '이미지 저장을 취소했습니다.' : '고화질 명세서 이미지를 저장했습니다.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('명세서 이미지 저장 실패: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePdf() async {
    final image = _template;
    if (image == null || _freight == null) return;
    setState(() => _saving = true);
    try {
      final png = await _renderPng();
      final logical = _logicalSize(image);
      final pdf = await DocumentPdfExport.statementTwoUp(
        png,
        sourceWidth: logical.width,
        sourceHeight: logical.height,
      );
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final safeReceipt = widget.receiptNumber.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]+'),
        '_',
      );
      final saved = await FilePicker.saveFile(
        dialogTitle: '명세서 출력용 PDF 저장 위치 선택',
        fileName:
            '${prefix.isEmpty ? 'STATEMENT' : prefix}_STATEMENT_$safeReceipt.pdf',
        bytes: pdf,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null ? 'PDF 저장을 취소했습니다.' : '출력용 PDF를 저장했습니다.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('출력용 PDF 저장 실패: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final image = _template;
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
                      '${widget.receiptNumber} · 명세서 보기',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
                    : image == null || _freight == null
                        ? const Center(
                            child: Text(
                              '명세서 폼을 불러오지 못했습니다.',
                              style: TextStyle(color: Colors.white),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: Center(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final logical = _logicalSize(image);
                                  final doc = _documentRect(image);
                                  final width =
                                      constraints.maxWidth.clamp(320.0, 760.0);
                                  return SizedBox(
                                    width: width,
                                    height: width * doc.height / doc.width,
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
                                                painter: _painter(image),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
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
                      onPressed: image == null || _freight == null || _saving
                          ? null
                          : _save,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('이미지 저장'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: image == null || _freight == null || _saving
                          ? null
                          : _savePdf,
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

class _StatementPainter extends CustomPainter {
  const _StatementPainter({
    required this.template,
    required this.routeLabel,
    required this.rows,
    required this.freight,
    required this.receiptNumber,
    required this.arrivalDate,
    required this.baseRows,
    required this.detailRows,
    required this.sourceTop,
  });

  final ui.Image template;
  final String routeLabel;
  final List<Map<String, dynamic>> rows;
  final FreightCalculation freight;
  final String receiptNumber;
  final String? arrivalDate;
  final int baseRows;
  final int detailRows;
  final double sourceTop;

  @override
  void paint(Canvas canvas, Size size) {
    final w = template.width.toDouble();
    final fullH = template.height.toDouble();
    final h = fullH - sourceTop;
    final rowH = h * .0220;
    final bodyTop = h * .1830;
    final bodyBottom = bodyTop + baseRows * rowH;
    final extra = (detailRows - baseRows) * rowH;
    final p = Paint()..filterQuality = FilterQuality.high;

    if (extra <= 0) {
      canvas.drawImageRect(
        template,
        Rect.fromLTWH(0, sourceTop, w, h),
        Rect.fromLTWH(0, 0, w, h),
        p,
      );
    } else {
      canvas.drawImageRect(
        template,
        Rect.fromLTWH(0, sourceTop, w, bodyBottom),
        Rect.fromLTWH(0, 0, w, bodyBottom),
        p,
      );
      final srcRow = Rect.fromLTWH(0, sourceTop + bodyBottom - rowH, w, rowH);
      for (var i = 0; i < detailRows - baseRows; i++) {
        canvas.drawImageRect(
          template,
          srcRow,
          Rect.fromLTWH(0, bodyBottom + i * rowH, w, rowH),
          p,
        );
      }
      canvas.drawImageRect(
        template,
        Rect.fromLTWH(0, sourceTop + bodyBottom, w, h - bodyBottom),
        Rect.fromLTWH(0, bodyBottom + extra, w, h - bodyBottom),
        p,
      );
    }

    if (RouteCatalog.usesInheritedForm(routeLabel)) {
      if (RouteCatalog.usesInheritedForm(routeLabel)) {
      _paintRouteTitle(canvas, w, h);
    }
    }

    // Excel 원본의 선/색/폰트/셀 서식을 그대로 유지한다.
    // 값이 들어가는 셀의 '안쪽'만 지워서 border는 절대 덮지 않는다.
    final xx = <double>[
      w * .0020, w * .0600, w * .1510, w * .1790, w * .2210,
      w * .3030, w * .4120, w * .4400, w * .4700, w * .5010,
      w * .5990, w * .7120, w * .8180, w * .9010, w * .9980,
    ];
    final white = Paint()..color = Colors.white;

    void clearCell(int c, double top, double bottom) {
      if (c < 0 || c >= xx.length - 1) return;
      canvas.drawRect(
        Rect.fromLTRB(
          xx[c] + 2.0,
          top + 2.0,
          xx[c + 1] - 2.0,
          bottom - 2.0,
        ),
        white,
      );
    }

    // 고객명/연락처/영수번호 영역도 셀 border를 남기고 내부만 갱신.
    canvas.drawRect(
      Rect.fromLTRB(w * .575, h * .062, w * .997, h * .118),
      white,
    );
    _text(canvas, receiptNumber, Offset(w * .865, h * .073), w * .11,
        fontSize: w * .018, bold: true);
    final first = rows.first;
    _text(
      canvas,
      '${first['consignee_name'] ?? MoneyFormat.number(freight.totalKip)}',
      Offset(w * .72, h * .073),
      w * .14,
      fontSize: w * .014,
      bold: true,
    );
    if (arrivalDate != null) {
      _text(
        canvas,
        arrivalDate!,
        Offset(w * .35, h * .073),
        w * .20,
        fontSize: w * .012,
      );
    }

    final lines = freight.lines;
    for (var i = 0; i < rows.length && i < detailRows; i++) {
      final r = rows[i];
      final y = bodyTop + i * rowH + rowH * .16;
      final line = i < lines.length ? lines[i] : null;
      final cellTop = bodyTop + i * rowH;
      final cellBottom = cellTop + rowH;
      for (var c = 0; c < xx.length - 1; c++) {
        clearCell(c, cellTop, cellBottom);
      }
      _text(canvas, '${i + 1}', Offset(w * .018, y), w * .04, fontSize: w * .010);
      _text(canvas, '${r['contents'] ?? MoneyFormat.number(freight.totalKip)}', Offset(w * .075, y), w * .11,
          fontSize: w * .009);
      _text(canvas, '${r['quantity'] ?? 1}', Offset(w * .22, y), w * .05,
          fontSize: w * .009);
      _text(canvas, '${r['weight_kg'] ?? MoneyFormat.number(freight.totalKip)}', Offset(w * .29, y), w * .07,
          fontSize: w * .009);
      _text(
        canvas,
        '${r['length_cm'] ?? MoneyFormat.number(freight.totalKip)}×${r['width_cm'] ?? MoneyFormat.number(freight.totalKip)}×${r['height_cm'] ?? MoneyFormat.number(freight.totalKip)}',
        Offset(w * .47, y),
        w * .13,
        fontSize: w * .0085,
      );
      if (line != null) {
        _text(
          canvas,
          line.chargeableWeight.toStringAsFixed(2),
          Offset(w * .66, y),
          w * .08,
          fontSize: w * .009,
        );
        _text(
          canvas,
          '\$${line.amountUsd.toStringAsFixed(2)}',
          Offset(w * .90, y),
          w * .08,
          fontSize: w * .009,
          bold: true,
        );
      }
    }

    final shift = extra;
    final totalY = h * .465 + shift;
    _text(
      canvas,
      '\$${freight.totalUsd.toStringAsFixed(2)}',
      Offset(w * .90, totalY),
      w * .08,
      fontSize: w * .012,
      bold: true,
    );
    _text(
      canvas,
      '${freight.totalKip.toStringAsFixed(0)}',
      Offset(w * .90, totalY + h * .026),
      w * .08,
      fontSize: w * .011,
      bold: true,
    );
    _text(
      canvas,
      '${freight.totalThb.toStringAsFixed(1)}',
      Offset(w * .90, totalY + h * .052),
      w * .08,
      fontSize: w * .011,
      bold: true,
    );
    _text(
      canvas,
      '${freight.totalKrw.toStringAsFixed(0)}',
      Offset(w * .90, totalY + h * .078),
      w * .08,
      fontSize: w * .011,
      bold: true,
    );
  }

  void _paintRouteTitle(Canvas canvas, double w, double h) {
    final documentTitle = RouteCatalog.documentTitleFor(routeLabel);
    // 실제 Excel 명세서 form의 제목 셀만 현재 route document_title로 갱신.
    final rect = Rect.fromLTRB(w * .19, h * .008, w * .81, h * .073);
    canvas.drawRect(
      rect,
      Paint()..color = Colors.white,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: '$documentTitle xxth 거래 명세서',
        style: TextStyle(
          color: Colors.black,
          fontFamily: 'NotoSansKR',
          fontSize: w * .030,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);
    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth, {
    required double fontSize,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _StatementPainter oldDelegate) => true;
}











