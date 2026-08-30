import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money_format.dart';
import '../core/route_catalog.dart';
import '../services/document_pdf_export.dart';
import '../services/freight_service.dart';
import '../services/statement_service.dart';


double _d(dynamic value, [double fallback = 0]) =>
    double.tryParse('${value ?? ''}'.trim()) ?? fallback;

String _s(dynamic value) => '${value ?? ''}'.trim();

String _fmtWeight(double v) {
  if ((v - v.roundToDouble()).abs() < .001) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}


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
  List<Map<String, dynamic>> _rows = const [];
  FreightCalculation? _freight;
  String? _arrivalDate;
  ui.Image? _logo;
  ui.Image? _qrUsd;
  ui.Image? _qrKip;
  ui.Image? _qrThb;
  ui.Image? _stamp;
  ui.Image? _bankStrip;
  bool _loading = true;
  bool _saving = false;

  static const double _docWidth = 1800;
  int get _visibleRows => _rows.length + 1 < 10 ? 10 : _rows.length + 1;
  double get _docHeight => 1120 + (_visibleRows - 10) * 32;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    try {
      final assets = await Future.wait<ui.Image>([
        _assetImage('assets/images/company_logo_transparent.png'),
        _assetImage('assets/images/payment_qr_usd.png'),
        _assetImage('assets/images/payment_qr_kip.png'),
        _assetImage('assets/images/payment_qr_thb.png'),
        _assetImage('assets/images/company_stamp.png'),
        _assetImage('assets/images/bank_accounts_strip.png'),
      ]);
      final rows = await StatementService.instance.rowsForReceipt(
        route: widget.routeLabel,
        year: widget.year,
        voyage: widget.voyage,
        receiptNumber: widget.receiptNumber,
      );
      if (rows.isEmpty) {
        throw StateError('명세서에 표시할 화물 데이터가 없습니다.');
      }
      final freight = await FreightService.instance.calculate(rows);
      final arrival = await StatementService.instance.arrivalDate(
        route: widget.routeLabel,
        year: widget.year,
        voyage: widget.voyage,
      );

      if (!mounted) return;
      setState(() {
        _logo = assets[0];
        _qrUsd = assets[1];
        _qrKip = assets[2];
        _qrThb = assets[3];
        _stamp = assets[4];
        _bankStrip = assets[5];
        _rows = rows;
        _freight = freight;
        _arrivalDate = arrival;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('명세서 로딩 실패: $error')));
    }
  }

  _DigitalStatementPainter get _painter => _DigitalStatementPainter(
        routeLabel: widget.routeLabel,
        rows: _rows,
        freight: _freight!,
        receiptNumber: widget.receiptNumber,
        arrivalDate: _arrivalDate,
        logo: _logo!,
        qrUsd: _qrUsd!,
        qrKip: _qrKip!,
        qrThb: _qrThb!,
        stamp: _stamp!,
        bankStrip: _bankStrip!,
      );

  Future<Uint8List> _renderPng() async {
    if (_freight == null || _logo == null) {
      throw StateError('명세서 데이터가 준비되지 않았습니다.');
    }
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
      final receipt = widget.receiptNumber
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final path = await FilePicker.saveFile(
        dialogTitle: '명세서 이미지 저장',
        fileName:
            '${prefix.isEmpty ? 'STATEMENT' : prefix}_STATEMENT_$receipt.png',
        bytes: bytes,
        mimeType: 'image/png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path == null ? '저장을 취소했습니다.' : '명세서 이미지를 저장했습니다.')),
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
      final pdf = await DocumentPdfExport.statementTwoUp(
        png,
        sourceWidth: _docWidth,
        sourceHeight: _docHeight,
      );
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final receipt = widget.receiptNumber
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final path = await FilePicker.saveFile(
        dialogTitle: '명세서 출력용 PDF 저장',
        fileName:
            '${prefix.isEmpty ? 'STATEMENT' : prefix}_STATEMENT_$receipt.pdf',
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
    final ready = !_loading && _freight != null && _logo != null && _stamp != null && _bankStrip != null;
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
                      '${widget.receiptNumber} · 명세서',
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
                    : !ready
                        ? const Center(
                            child: Text(
                              '명세서를 불러오지 못했습니다.',
                              style: TextStyle(color: Colors.white),
                            ),
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

class _DigitalStatementPainter extends CustomPainter {
  const _DigitalStatementPainter({
    required this.routeLabel,
    required this.rows,
    required this.freight,
    required this.receiptNumber,
    required this.arrivalDate,
    required this.logo,
    required this.qrUsd,
    required this.qrKip,
    required this.qrThb,
    required this.stamp,
    required this.bankStrip,
  });

  final String routeLabel;
  final List<Map<String, dynamic>> rows;
  final FreightCalculation freight;
  final String receiptNumber;
  final String? arrivalDate;
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
    final w = size.width;
    final h = size.height;
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final border = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _imageContain(c, logo, Rect.fromLTWH(18, 8, 135, 72));
    _text(c, '${RouteCatalog.documentTitleFor(routeLabel)} 거래 명세서',
        Rect.fromLTWH(0, 12, w, 62),
        39,
        bold: true,
        center: true);
    _labelValue(c, '구획(Zone)', _s(rows.first['zone']),
        Rect.fromLTWH(w - 300, 8, 282, 72), valueSize: 34);

    final infoTop = 90.0;
    const infoH = 106.0;
    final half = w * .5;
    for (var r = 0; r < 3; r++) {
      final y = infoTop + r * (infoH / 3);
      _box(c, Rect.fromLTWH(0, y, half, infoH / 3), paleBlue.withOpacity(.38));
      _box(c, Rect.fromLTWH(half, y, half, infoH / 3), paleBlue.withOpacity(.38));
    }
    _kv(c, '회사명', '엘케이(LK)무역', Rect.fromLTWH(8, infoTop + 7, half - 16, 28));
    _kv(c, '회사주소', '비엔티엔시, 씨싿따낙구, 싸판텅 느아 09, 11번 골목, 엘케이(LK) 빌딩, 1층 LK Trading', Rect.fromLTWH(8, infoTop + 39, half - 16, 28));
    _kv(c, '전화번호', '+856 20 9112 6780', Rect.fromLTWH(8, infoTop + 71, half - 16, 28));
    
    _kv(c, '고객명/회사명', _s(rows.first['consignee_name']),
        Rect.fromLTWH(half + 8, infoTop + 4, half - 16, 28), emphasize: true);
    _kv(c, '연락처', _s(rows.first['consignee_phone']),
        Rect.fromLTWH(half + 8, infoTop + 39, half - 16, 28), emphasize: true);
    _kv(c, '영수번호', receiptNumber, Rect.fromLTWH(half + 8, infoTop + 74, half - 16, 28), emphasize: true);

    const tableTop = 205.0;
    const headerH = 42.0;
    const rowH = 32.0;
    final rowCount = rows.length + 1 < 10 ? 10 : rows.length + 1;
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
      _text(c, headers[i], r.deflate(3), 16, bold: true, center: true);
    }

    final lines = freight.lines;
    for (var i = 0; i < rowCount; i++) {
      final y = tableTop + headerH + i * rowH;
      final has = i < rows.length;
      final row = has ? rows[i] : const <String, dynamic>{};
      final f = i < lines.length ? lines[i] : null;
      final actualWins = f != null && f.actualWeight >= f.volumeWeight;
      final volumeWins = f != null && f.volumeWeight > f.actualWeight;

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
      if (!has) continue;
      final qty = _d(row['quantity'], 1).clamp(1, 999999).toDouble();
      final unitActual = f == null ? 0.0 : f.actualWeight / qty;
      final unitVolume = f == null ? 0.0 : f.volumeWeight / qty;
      final actualFreight = f == null ? 0.0 : f.actualWeight * f.rate;
      final volumeFreight = f == null ? 0.0 : f.volumeWeight * f.rate;
      final values = <String>[
        _s(row['box_number']),
        f == null ? '-' : '\$${f.rate.toStringAsFixed(2)}',
        _s(row['quantity']).isEmpty ? '1' : _s(row['quantity']),
        f == null ? '-' : _fmtWeight(unitActual),
        f == null ? '-' : _fmtWeight(f.actualWeight),
        _s(row['length_cm']),
        _s(row['width_cm']),
        _s(row['height_cm']),
        f == null ? '-' : _fmtWeight(unitVolume),
        f == null ? '-' : _fmtWeight(f.volumeWeight),
        f == null ? '-' : MoneyFormat.usd(actualFreight),
        f == null ? '-' : MoneyFormat.usd(volumeFreight),
        f == null ? '-' : MoneyFormat.usd(f.amountUsd),
      ];
      for (var col = 0; col < values.length; col++) {
        _text(c, values[col],
            Rect.fromLTRB(cols[col + 1] + 3, y + 2, cols[col + 2] - 3, y + rowH - 2),
            col >= 10 && col <= 12 ? 18 : 16,
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
    final totalQty = rows.fold<double>(0, (v, r) => v + _d(r['quantity'], 1));
    final totalActual = freight.lines.fold<double>(0, (v, f) => v + f.actualWeight);
    final totalVolume = freight.lines.fold<double>(0, (v, f) => v + f.volumeWeight);
    final summaryValues = <int, String>{
      1: '합계',
      3: _fmtWeight(totalQty),
      5: _fmtWeight(totalActual),
      10: _fmtWeight(totalVolume),
      13: MoneyFormat.usd(freight.totalUsd),
    };
    for (final e in summaryValues.entries) {
      _text(c, e.value,
          Rect.fromLTRB(cols[e.key] + 4, summaryY + 2, cols[e.key + 1] - 4, summaryY + rowH - 2),
          16, bold: true, center: true);
    }

    final sumTop = summaryY + rowH + 10;
    final leftW = w * .70;
    _box(c, Rect.fromLTWH(0, sumTop, leftW * .58, 160), const Color(0xFFFBFCFD));
    _box(c, Rect.fromLTWH(leftW * .58 + 4, sumTop, leftW * .42 - 4, 160), const Color(0xFFF3F8FC));
    _text(c, 'Remark/비고', Rect.fromLTWH(10, sumTop + 7, leftW * .58 - 20, 24),
        17, bold: true);
    _text(c, RouteCatalog.remarkFor(routeLabel).isEmpty
        ? '운임은 DB 공통 운임정책 및 실제/용적 중 큰 청구중량 기준으로 계산됩니다.'
        : RouteCatalog.remarkFor(routeLabel),
        Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112), 14);

    _text(c, 'Inland delivery/시내·지방 배송',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 7, leftW * .42 - 24, 24),
        18, bold: true);
    

    final totalX = leftW + 6;
    final totalW = w - totalX;
    _box(c, Rect.fromLTWH(totalX, sumTop, totalW, 190), totalColor);
    final adjH = 25.0;
    _text(c, '할인', Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 7, totalW * .44, adjH), 16, bold: true, right: true);
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
    _text(c, '세금 계산서(VAT)', Rect.fromLTWH(totalX + 12, sumTop + 61, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 61, totalW * .44, adjH), 16, bold: true, right: true);

    final finalTop = sumTop + 92;
    final labelW = totalW * .38;
    _box(c, Rect.fromLTWH(totalX, finalTop, labelW, 94), const Color(0xFFFFF200));
    _text(c, '최종 명세서 총액', Rect.fromLTWH(totalX + 8, finalTop + 6, labelW - 16, 82),
        19, bold: true, center: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 0 * 23.5, totalW - labelW, 23.5),
        const Color(0xFFFCE48A));
    _text(c, 'USD    ' + MoneyFormat.usd(freight.totalUsd),
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 0 * 23.5, totalW - labelW - 16, 23.5),
        18, bold: true, center: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 1 * 23.5, totalW - labelW, 23.5),
        const Color(0xFFFFC21A));
    _text(c, 'KIP    ' + MoneyFormat.kip(freight.totalKip),
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 1 * 23.5, totalW - labelW - 16, 23.5),
        18, bold: true, center: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 2 * 23.5, totalW - labelW, 23.5),
        const Color(0xFF91D18B));
    _text(c, 'THB    ' + MoneyFormat.thb(freight.totalThb),
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 2 * 23.5, totalW - labelW - 16, 23.5),
        18, bold: true, center: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 3 * 23.5, totalW - labelW, 23.5),
        const Color(0xFF23B6D8));
    _text(c, 'KRW    ' + MoneyFormat.krw(freight.totalKrw),
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 3 * 23.5, totalW - labelW - 16, 23.5),
        18, bold: true, center: true);
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
      18,
      bold: true,
      center: true,
    );

    final noteTop = payTop + 150;
    _text(
      c,
      '* 입·출고지를 떠나기 전 고객님 운임 물품 및 개수 확인 부탁드립니다.  '
      '* 물품 출고 후 1주 후부터 보관료가 발생할 수 있습니다.  '
      '* 이용해 주셔서 감사합니다.',
      Rect.fromLTWH(15, noteTop, w - 30, 42),
      13,
      center: true,
    );

    final signTop = noteTop + 46;
    final signW = w * .26;
    final signH = 105.0;
    _box(c, Rect.fromLTWH(0, signTop, signW, signH), Colors.white);
    _box(c, Rect.fromLTWH(w - signW, signTop, signW, signH), Colors.white);
    _text(c, '엘케이 (LK)무역', Rect.fromLTWH(18, signTop + 14, signW - 36, 30),
        20, bold: true);
    _imageContain(c, stamp, Rect.fromLTWH((signW - 105) / 2, signTop + 34, 105, 64));
    final routeNotice = RouteCatalog.remarkFor(routeLabel);
    _text(
      c,
      routeNotice.isEmpty ? '* 입·출고지를 떠나기 전 운임 물품 및 개수 확인 부탁드립니다.  * 물품 출고 후 보관료가 발생할 수 있습니다.  * 이용해 주셔서 감사합니다.' : routeNotice,
      Rect.fromLTWH(signW + 18, signTop + 6, w - signW * 2 - 36, signH - 12),
      13,
      center: true,
    );
    _text(c, '고객사 서명', Rect.fromLTWH(w - signW + 18, signTop + 14, signW - 36, 30),
        18, bold: true);

    c.drawRect(Offset.zero & size, border);
  }

  void _payment(Canvas c, ui.Image image, String title, String detail, Rect r) {
    _imageContain(c, image, Rect.fromLTWH(r.left + 6, r.top + 6, 132, 132));
    _text(c, title, Rect.fromLTWH(r.left + 144, r.top + 8, r.width - 150, 30),
        19, bold: true, center: true);
    _text(c, detail, Rect.fromLTWH(r.left + 144, r.top + 40, r.width - 150, 98),
        16, bold: true);
  }

  void _kv(Canvas c, String k, String v, Rect r, {bool emphasize = false}) {
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
      v.isEmpty ? '-' : v,
      Rect.fromLTWH(r.left + labelW, r.top, r.width - labelW, r.height),
      emphasize ? 21 : 19,
      bold: emphasize,
      center: true,
    );
  }

  void _labelValue(Canvas c, String label, String value, Rect r,
      {double valueSize = 30}) {
    _box(c, r, paleBlue);
    _text(c, label, Rect.fromLTWH(r.left, r.top + 4, r.width, 22),
        14, bold: true, center: true);
    _text(c, value.isEmpty ? '-' : value,
        Rect.fromLTWH(r.left, r.top + 26, r.width, r.height - 30),
        valueSize, bold: true, center: true);
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
      {bool bold = false, bool center = false, bool right = false}) {
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
      textAlign: center ? TextAlign.center : (right ? TextAlign.right : TextAlign.left),
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: r.width);
    final y = r.top + (r.height - p.height).clamp(0, r.height) / 2;
    final x = center ? r.left + (r.width - p.width) / 2 : (right ? r.right - p.width : r.left);
    p.paint(c, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _DigitalStatementPainter oldDelegate) => true;
}

