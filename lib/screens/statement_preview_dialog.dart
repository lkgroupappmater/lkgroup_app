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
  bool _loading = true;
  bool _saving = false;

  static const double _docWidth = 1800;
  int get _visibleRows => _rows.length < 10 ? 10 : _rows.length;
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
    final ready = !_loading && _freight != null && _logo != null && _stamp != null;
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
        Rect.fromLTWH(190, 16, 940, 58),
        39,
        bold: true,
        center: true);
    _labelValue(c, '구획(Zone)', _s(rows.first['zone']),
        Rect.fromLTWH(w - 300, 8, 282, 72), valueSize: 34);

    final infoTop = 90.0;
    final half = w * .5;
    _box(c, Rect.fromLTWH(0, infoTop, half, 72), paleBlue.withOpacity(.38));
    _box(c, Rect.fromLTWH(half, infoTop, half, 72), paleBlue.withOpacity(.38));
    _kv(c, '회사명', '엘케이(LK)무역', Rect.fromLTWH(8, infoTop + 2, half - 16, 24));
    _kv(c, '회사주소', 'Vientiane Capital, Lao PDR', Rect.fromLTWH(8, infoTop + 25, half - 16, 22));
    _kv(c, '전화번호', '+856 (0)20 5559 8916', Rect.fromLTWH(8, infoTop + 47, half - 16, 22));
    
    _kv(c, '고객명/회사명', _s(rows.first['consignee_name']),
        Rect.fromLTWH(half + 8, infoTop + 4, half - 16, 28), emphasize: true);
    _kv(c, '연락처', _s(rows.first['consignee_phone']),
        Rect.fromLTWH(half + 8, infoTop + 34, half - 180, 28), emphasize: true);
    _text(c, receiptNumber, Rect.fromLTWH(w - 170, infoTop + 33, 158, 30),
        23, bold: true, center: true);

    const tableTop = 170.0;
    const headerH = 42.0;
    const rowH = 32.0;
    final rowCount = rows.length < 10 ? 10 : rows.length;
    final cols = <double>[
      0, 105, 220, 300, 420, 550, 650, 750, 850, 980, 1110, 1245, 1380, 1515, 1800
    ];
    final headers = <String>[
      '박스번호', '단가', '수량', '실제중량(kg)', '실제중량 합산(kg)',
      'L', 'W', 'H', '용적중량(kg)', '용적중량 합산(kg)',
      '실제중량 운임', '용적중량 운임', '청구중량 운임', '비고'
    ];
    final fills = <Color?>[
      null, null, null, actualColor, actualColor, null, null, null,
      volumeColor, volumeColor, actualColor, volumeColor, appliedColor, null
    ];
    for (var i = 0; i < headers.length; i++) {
      final r = Rect.fromLTRB(cols[i], tableTop, cols[i + 1], tableTop + headerH);
      _box(c, r, fills[i] ?? const Color(0xFFF6F7F9));
      _text(c, headers[i], r.deflate(3), 15, bold: true, center: true);
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
        if (has && (col == 3 || col == 4 || col == 10) && actualWins) fill = actualColor;
        if (has && (col == 8 || col == 9 || col == 11) && volumeWins) fill = volumeColor;
        if (has && col == 12) fill = appliedColor;
        _box(c, Rect.fromLTRB(cols[col], y, cols[col + 1], y + rowH), fill);
      }
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
        actualWins ? '실중량 적용' : (volumeWins ? '용적 적용' : ''),
      ];
      for (var col = 0; col < values.length; col++) {
        _text(c, values[col],
            Rect.fromLTRB(cols[col] + 3, y + 2, cols[col + 1] - 3, y + rowH - 2),
            col >= 10 && col <= 12 ? 16 : 15,
            bold: col == 4 || col == 9 || col == 12,
            center: true);
      }
    }

    final sumTop = tableTop + headerH + rowCount * rowH + 8;
    final leftW = w * .70;
    _box(c, Rect.fromLTWH(0, sumTop, leftW * .58, 120), const Color(0xFFFBFCFD));
    _box(c, Rect.fromLTWH(leftW * .58 + 4, sumTop, leftW * .42 - 4, 120), const Color(0xFFF3F8FC));
    _text(c, 'Remark/비고', Rect.fromLTWH(10, sumTop + 7, leftW * .58 - 20, 24),
        17, bold: true);
    _text(c, RouteCatalog.remarkFor(routeLabel).isEmpty
        ? '운임은 DB 공통 운임정책 및 실제/용적 중 큰 청구중량 기준으로 계산됩니다.'
        : RouteCatalog.remarkFor(routeLabel),
        Rect.fromLTWH(10, sumTop + 35, leftW * .58 - 20, 76), 14);

    _text(c, 'Inland delivery/시내·지방 배송',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 7, leftW * .42 - 24, 24),
        18, bold: true);
    _text(c, '배송비/선불·착불/배송업체 등 추후 입력',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 38, leftW * .42 - 24, 65),
        15);

    final totalX = leftW + 6;
    final totalW = w - totalX;
    _box(c, Rect.fromLTWH(totalX, sumTop, totalW, 120), totalColor);
    _text(c, '운임 총합  ${MoneyFormat.usd(freight.totalUsd)}    할인  -    특별할인  -    세금계산서(VAT)  -',
        Rect.fromLTWH(totalX + 10, sumTop + 5, totalW - 20, 26),
        16, bold: true);
    _text(c, '최종 청구 금액', Rect.fromLTWH(totalX + 8, sumTop + 31, totalW - 16, 24),
        18, bold: true, center: true);
    final money = <String>[
      'USD  ${MoneyFormat.usd(freight.totalUsd)}',
      'KIP  ${MoneyFormat.kip(freight.totalKip)}',
      'THB  ${MoneyFormat.thb(freight.totalThb)}',
      'KRW  ${MoneyFormat.krw(freight.totalKrw)}',
    ];
    for (var i = 0; i < money.length; i++) {
      _text(c, money[i],
          Rect.fromLTWH(totalX + 15, sumTop + 55 + i * 16, totalW - 30, 20),
          19, bold: true, center: true);
    }

    final payTop = sumTop + 132;
    _payment(c, qrUsd, 'BCEL (USD)', '(SungHo Park)\n010-12-01-\n017655-60-001',
        Rect.fromLTWH(6, payTop, w * .235, 145));
    _payment(c, qrKip, 'BCEL (KIP)', '(SungHo Park)\n013-12-00-\n017655-60-001',
        Rect.fromLTWH(w * .25, payTop, w * .235, 145));
    _payment(c, qrThb, 'BCEL (Baht)', '(SungHo Park)\n010-12-02-\n017655-60-001',
        Rect.fromLTWH(w * .50, payTop, w * .235, 145));

    _payment(c, qrUsd, '한국 계좌 (KRW)', '은행/계좌 정보\n추후 확정 기입',
        Rect.fromLTWH(w * .75, payTop, w * .235, 145));

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
    _box(c, Rect.fromLTWH(0, signTop, w * .48, h - signTop - 2), Colors.white);
    _box(c, Rect.fromLTWH(w * .52, signTop, w * .48, h - signTop - 2), Colors.white);
    _text(c, '엘케이 (LK)무역', Rect.fromLTWH(18, signTop + 14, w * .42, 30),
        20, bold: true);
    _imageContain(c, stamp, Rect.fromLTWH(w * .29, signTop + 10, 125, 95));
    _text(c, '고객사 서명', Rect.fromLTWH(w * .54, signTop + 14, w * .42, 30),
        18, bold: true);

    c.drawRect(Offset.zero & size, border);
  }

  void _payment(Canvas c, ui.Image image, String title, String detail, Rect r) {
    _image(c, image, Rect.fromLTWH(r.left + 4, r.top + 2, 128, 128));
    _text(c, title, Rect.fromLTWH(r.left + 140, r.top + 10, r.width - 145, 28),
        19, bold: true);
    _text(c, detail, Rect.fromLTWH(r.left + 140, r.top + 38, r.width - 145, 92),
        16, bold: true);
  }

  void _kv(Canvas c, String k, String v, Rect r, {bool emphasize = false}) {
    _text(c, '$k  ', Rect.fromLTWH(r.left, r.top, 145, r.height), 15, bold: true);
    _text(c, v.isEmpty ? '-' : v,
        Rect.fromLTWH(r.left + 145, r.top, r.width - 145, r.height),
        emphasize ? 19 : 16,
        bold: emphasize);
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
  bool shouldRepaint(covariant _DigitalStatementPainter oldDelegate) => true;
}
