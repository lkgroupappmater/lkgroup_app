import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/route_catalog.dart';
import '../services/freight_service.dart';
import '../services/statement_service.dart';

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

  Size _logicalSize(ui.Image image) {
    final rowHeight = image.height * .028;
    final extra = (_detailRows - _baseRows) * rowHeight;
    return Size(image.width.toDouble(), image.height + extra);
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
      );

  Future<Uint8List> _renderPng() async {
    final image = _template;
    if (image == null || _freight == null) {
      throw StateError('명세서를 아직 불러오지 못했습니다.');
    }
    final size = _logicalSize(image);
    const scale = 1.75;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale, scale);
    _painter(image).paint(canvas, size);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      (size.width * scale).round(),
      (size.height * scale).round(),
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
                                  final width =
                                      constraints.maxWidth.clamp(320.0, 760.0);
                                  return SizedBox(
                                    width: width,
                                    height: width *
                                        logical.height /
                                        logical.width,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        width: logical.width,
                                        height: logical.height,
                                        child: CustomPaint(
                                          painter: _painter(image),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          image == null || _freight == null || _saving ? null : _save,
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
  });

  final ui.Image template;
  final String routeLabel;
  final List<Map<String, dynamic>> rows;
  final FreightCalculation freight;
  final String receiptNumber;
  final String? arrivalDate;
  final int baseRows;
  final int detailRows;

  @override
  void paint(Canvas canvas, Size size) {
    final w = template.width.toDouble();
    final h = template.height.toDouble();
    final rowH = h * .028;
    final bodyTop = h * .245;
    final bodyBottom = bodyTop + baseRows * rowH;
    final extra = (detailRows - baseRows) * rowH;
    final p = Paint()..filterQuality = FilterQuality.high;

    if (extra <= 0) {
      canvas.drawImage(template, Offset.zero, p);
    } else {
      canvas.drawImageRect(
        template,
        Rect.fromLTWH(0, 0, w, bodyBottom),
        Rect.fromLTWH(0, 0, w, bodyBottom),
        p,
      );
      final srcRow = Rect.fromLTWH(0, bodyBottom - rowH, w, rowH);
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
        Rect.fromLTWH(0, bodyBottom, w, h - bodyBottom),
        Rect.fromLTWH(0, bodyBottom + extra, w, h - bodyBottom),
        p,
      );
    }

    _paintRouteTitle(canvas, w, h);

    // 기존 샘플 값만 흰색으로 지우고 실제 DB 값을 오버레이.
    final white = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(w * .57, h * .09, w * .40, h * .075), white);
    canvas.drawRect(Rect.fromLTWH(w * .005, bodyTop, w * .985, rowH * baseRows), white);

    final grid = Paint()
      ..color = const Color(0xFF777777)
      ..strokeWidth = 1;
    for (var i = 0; i <= detailRows; i++) {
      final y = bodyTop + i * rowH;
      canvas.drawLine(Offset(w * .005, y), Offset(w * .99, y), grid);
    }

    _text(canvas, receiptNumber, Offset(w * .865, h * .105), w * .11,
        fontSize: w * .018, bold: true);
    final first = rows.first;
    _text(
      canvas,
      '${first['consignee_name'] ?? ''}',
      Offset(w * .72, h * .105),
      w * .14,
      fontSize: w * .014,
      bold: true,
    );
    if (arrivalDate != null) {
      _text(
        canvas,
        arrivalDate!,
        Offset(w * .35, h * .105),
        w * .20,
        fontSize: w * .012,
      );
    }

    final lines = freight.lines;
    for (var i = 0; i < rows.length && i < detailRows; i++) {
      final r = rows[i];
      final y = bodyTop + i * rowH + rowH * .18;
      final line = i < lines.length ? lines[i] : null;
      _text(canvas, '${i + 1}', Offset(w * .018, y), w * .04, fontSize: w * .010);
      _text(canvas, '${r['contents'] ?? ''}', Offset(w * .075, y), w * .11,
          fontSize: w * .009);
      _text(canvas, '${r['quantity'] ?? 1}', Offset(w * .22, y), w * .05,
          fontSize: w * .009);
      _text(canvas, '${r['weight_kg'] ?? ''}', Offset(w * .29, y), w * .07,
          fontSize: w * .009);
      _text(
        canvas,
        '${r['length_cm'] ?? ''}×${r['width_cm'] ?? ''}×${r['height_cm'] ?? ''}',
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
    final totalY = h * .53 + shift;
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
      Offset(w * .90, totalY + h * .027),
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
      Offset(w * .90, totalY + h * .077),
      w * .08,
      fontSize: w * .011,
      bold: true,
    );
  }

  void _paintRouteTitle(Canvas canvas, double w, double h) {
    final documentTitle = RouteCatalog.documentTitleFor(routeLabel);
    // statement PNG는 상단에 원본 링크 이미지 여백이 있으므로 실제 문서 타이틀 위치에 덮어씀.
    final rect = Rect.fromLTRB(w * .19, h * .472, w * .81, h * .525);
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


