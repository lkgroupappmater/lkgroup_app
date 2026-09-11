import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;

import '../core/money_format.dart';
import '../core/route_catalog.dart';
import '../core/document_text_catalog.dart';
import '../core/document_form_style.dart';
import '../services/document_pdf_export.dart';
import '../services/freight_service.dart';
import '../services/statement_service.dart';
import '../services/customer_benefit_service.dart';
import '../services/receipt_extra_cost_service.dart';


double _d(dynamic value, [double fallback = 0]) =>
    double.tryParse('${value ?? ''}'.trim()) ?? fallback;

String _s(dynamic value) => '${value ?? ''}'.trim();

String _fmtWeight(double v) {
  if ((v - v.roundToDouble()).abs() < .001) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

Future<Uint8List> _encodeJpeg(
  ui.Image source, {
  int quality = 86,
}) async {
  final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('명세서 이미지 변환에 실패했습니다.');
  final pixels = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final bitmap = image_lib.Image.fromBytes(
    width: source.width,
    height: source.height,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    numChannels: 4,
    order: image_lib.ChannelOrder.rgba,
  );
  return image_lib.encodeJpg(bitmap, quality: quality);
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
  String _inlandDeliveryText = '';
  List<ExtraCostItem> _extraCosts = const <ExtraCostItem>[];
  ui.Image? _logo;
  ui.Image? _qrUsd;
  ui.Image? _qrKip;
  ui.Image? _qrThb;
  ui.Image? _stamp;
  ui.Image? _bankStrip;
  bool _loading = true;
  bool _saving = false;

  static const double _docWidth = DocumentFormStyle.width;
  double get _docHeight => _painter.documentHeight;

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
      final inland = await CustomerBenefitService.instance
          .inlandTextForRows(widget.routeLabel, rows);
      final extraCosts = await ReceiptExtraCostService.instance.list(
        route: widget.routeLabel,
        year: widget.year,
        voyage: widget.voyage,
        receiptNumber: widget.receiptNumber,
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
        _inlandDeliveryText = inland;
        _extraCosts = extraCosts;
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
        voyage: widget.voyage,
        inlandDeliveryText: _inlandDeliveryText,
        extraCosts: _extraCosts,
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

  Future<Uint8List> _renderPdfImage() async {
    if (_freight == null || _logo == null) {
      throw StateError('명세서 데이터가 준비되지 않았습니다.');
    }
    // PDF embeds JPEG directly. This avoids retaining a decoded high-resolution
    // PNG for every statement and substantially lowers Android heap usage.
    const scale = .9;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    _painter.paint(canvas, Size(_docWidth, _docHeight));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (_docWidth * scale).round(),
      (_docHeight * scale).round(),
    );
    picture.dispose();
    try {
      return await _encodeJpeg(image);
    } finally {
      image.dispose();
    }
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
      final encodedImage = await _renderPdfImage();
      final pdf = await DocumentPdfExport.statementTwoUp(
        encodedImage,
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
                color: const Color(0xFFEDF2F7),
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
    required this.voyage,
    required this.inlandDeliveryText,
    required this.extraCosts,
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
  final String voyage;
  final String inlandDeliveryText;
  final List<ExtraCostItem> extraCosts;
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

  DocumentTextContent get _docText => DocumentTextCatalog.statement(routeLabel, DateTime.now());
  String get _remarkText => _displayAutoNotes.isEmpty
      ? _docText.remark : '${_docText.remark}\n\n$_displayAutoNotes';

  DocumentFormLayout get _layout => DocumentFormLayout(
    itemCount: rows.length + extraCosts.length,
    remark: _remarkText, remarkFontSize: _docText.remarkFontSize,
    footer: _docText.footerText, footerFontSize: _docText.footerFontSize,
    delivery: inlandDeliveryText,
  );
  double get documentHeight => _layout.height;

  String get _displayAutoNotes {
    final autoNotes = rows
        .map((row) => _s(row['special_note_auto']))
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' / ');
    bool validDiscountGroup(String value) {
      final key = value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\s_./()-]+'), '');
      return key.isNotEmpty &&
          key != '할인' &&
          key != '할인율' &&
          key != '할인금액' &&
          key != '할인액' &&
          key != 'discount' &&
          key != 'discountrate' &&
          key != 'discountamount' &&
          key != '기타할인';
    }

    final freightGroups = freight.lines
        .map((line) => line.discountGroup.trim())
        .where(validDiscountGroup)
        .where((value) => value.isNotEmpty && value != '기타 할인')
        .toSet()
        .toList(growable: false);
    final freightDiscountPercent = freight.lines
        .map((line) => line.discountPercent)
        .fold<double>(0, (best, value) => value > best ? value : best);

    var displayAutoNotes = autoNotes;
    if (freightDiscountPercent > 0) {
      final group = freightGroups.isEmpty ? '' : freightGroups.first;
      final phrase = group.isEmpty
          ? '할인 ${pctText(freightDiscountPercent)}% 적용'
          : (group.contains('할인')
              ? '$group ${pctText(freightDiscountPercent)}% 적용'
              : '$group 할인 ${pctText(freightDiscountPercent)}% 적용');
      final parts = displayAutoNotes.isEmpty
          ? <String>[]
          : displayAutoNotes.split(' / ').map((e) => e.trim()).toList();
      final oldDiscount = parts.indexWhere(
        (e) => e.contains('할인') && e.contains('% 적용'),
      );
      if (oldDiscount >= 0) {
        parts[oldDiscount] = phrase;
      } else {
        final delivery = parts.indexWhere(
          (e) => e.contains('지방배송') || e.contains('시내배송'),
        );
        if (delivery >= 0) {
          parts.insert(delivery, phrase);
        } else {
          parts.add(phrase);
        }
      }
      displayAutoNotes = parts.where((e) => e.isNotEmpty).join(' / ');
    }
    return displayAutoNotes;
  }

  String pctText(double value) {
    final p = value * 100;
    return (p - p.roundToDouble()).abs() < .001
        ? p.toStringAsFixed(0)
        : p.toStringAsFixed(2);
  }


  @override
  void paint(Canvas c, Size size) {
    final layout = _layout;
    final w = size.width;
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final border = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _imageContain(c, logo, Rect.fromLTWH(18, 8, 135, 72));
    final voyageText = voyage.trim().isEmpty
        ? ''
        : (voyage.trim().endsWith('항차') ? voyage.trim() : '${voyage.trim()}항차');
    final statementTitle = voyageText.isEmpty
        ? '${RouteCatalog.documentTitleFor(routeLabel)} 거래 명세서'
        : '${RouteCatalog.documentTitleFor(routeLabel)} $voyageText 거래 명세서';

    _text(c, statementTitle,
        Rect.fromLTWH(180, 12, w - 510, 62),
        39,
        bold: true,
        center: true);
    _labelValue(c, '구획(Zone)', _s(rows.first['unloading_zone']),
        Rect.fromLTWH(w - 300, 8, 282, 72), valueSize: 34);

    const infoTop = 104.0;
    const infoH = 108.0;
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

    const tableTop = DocumentFormStyle.tableTop;
    const headerH = DocumentFormStyle.headerHeight;
    const rowH = DocumentFormStyle.rowHeight;
    final rowCount = layout.rowCount;
    final cols = <double>[
      0, 55, 170, 285, 365, 490, 620, 710, 800, 890, 1030, 1170, 1360, 1570, 1800
    ];
    final headers = <String>[
      'No.', '박스번호', '단가', '수량', '실제중량(kg)', '실제중량 합산(kg)',
      'L', 'W', 'H', '용적중량(kg)', '용적중량 합산(kg)',
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

    final lines = freight.lines;
    for (var i = 0; i < rowCount; i++) {
      final y = tableTop + headerH + i * rowH;
      final has = i < rows.length;
      final extraIndex = i - rows.length;
      final hasExtra = extraIndex >= 0 && extraIndex < extraCosts.length;
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
          17, bold: true, center: true);
      if (hasExtra) {
        final extra = extraCosts[extraIndex];
        _box(c, Rect.fromLTRB(cols[1], y, cols[13], y + rowH), const Color(0xFFF8FAFD));
        _text(
          c,
          extra.discountApplies ? '${extra.name} (할인)' : extra.name,
          Rect.fromLTRB(cols[1] + 12, y + 2, cols[13] - 12, y + rowH - 2),
          19,
          bold: true,
          center: false,
        );
        _text(
          c,
          MoneyFormat.usd(extra.amountUsd),
          Rect.fromLTRB(cols[13] + 3, y + 2, cols[14] - 3, y + rowH - 2),
          21,
          bold: true,
          right: true,
        );
        continue;
      }
      if (!has) continue;
      final qty = _d(row['quantity'], 1).clamp(1, 999999).toDouble();
      final unitActual = f == null ? 0.0 : f.actualWeight / qty;
      final unitVolume = f == null ? 0.0 : f.volumeWeight / qty;
      final actualFreight = f == null ? 0.0 : f.actualWeight * f.rate;
      final volumeFreight = f == null ? 0.0 : f.volumeWeight * f.rate;
      final values = <String>[
        _s(row['box_number']),
        f == null ? '-' : '\$ ${f.rate.toStringAsFixed(2)}',
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
        f == null ? '-' : MoneyFormat.usd(f.grossAmountUsd),
      ];
      for (var col = 0; col < values.length; col++) {
        _text(c, values[col],
            Rect.fromLTRB(cols[col + 1] + 3, y + 2, cols[col + 2] - 3, y + rowH - 2),
            col >= 10 && col <= 12 ? 21 : 19,
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
    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    // Use the actual discount rule from FreightService lines first.
    // Important: when freight is $0, gross/discount ratio is 0/0-ish and
    // previously made a checked extra cost receive no discount at all.
    final lineBaseDiscountPercent = freight.lines
        .map((line) => line.discountPercent)
        .fold<double>(0, (best, value) => value > best ? value : best);
    final baseDiscountPercent = lineBaseDiscountPercent > 0
        ? lineBaseDiscountPercent
        : (freight.grossTotalUsd <= 0
            ? 0.0
            : (freight.discountTotalUsd / freight.grossTotalUsd)
                .clamp(0.0, 1.0));
    final discountableExtraTotal = extraCosts
        .where((e) => e.discountApplies)
        .fold<double>(0, (sum, e) => sum + e.amountUsd);
    final extraDiscountUsd =
        discountableExtraTotal * baseDiscountPercent;
    final totalDiscountUsd =
        freight.discountTotalUsd + extraDiscountUsd;
    final grossUsd = freight.grossTotalUsd + extraTotal;
    final finalUsd = grossUsd - totalDiscountUsd;
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

    final sumTop = layout.summaryTop;
    final docText = _docText;
    final leftW = w * .70;
    _box(c, Rect.fromLTWH(0, sumTop, leftW * .58, layout.summaryHeight), const Color(0xFFFBFCFD));
    _box(c, Rect.fromLTWH(leftW * .58 + 4, sumTop, leftW * .42 - 4, layout.summaryHeight), const Color(0xFFF3F8FC));
    _text(c, 'Remark/비고', Rect.fromLTWH(10, sumTop + 7, leftW * .58 - 20, 30),
        19, bold: true);
    final displayAutoNotes = _displayAutoNotes;
    final remarkText = displayAutoNotes.isEmpty
        ? docText.remark
        : '${docText.remark}\n\n$displayAutoNotes';
    _text(
      c,
      remarkText,
      Rect.fromLTWH(10, sumTop + 44, leftW * .58 - 20, layout.summaryHeight - 60),
      docText.remarkFontSize,
      lineHeight: 1.2,
    );

    _text(c, 'Inland delivery/시내·지방 배송',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 7, leftW * .42 - 24, 30),
        19, bold: true);

    final deliveryNote = rows
        .map((e) => '${e['special_note_auto'] ?? e['special_note'] ?? ''}')
        .join(' ');
    Color? deliveryColor;
    if (deliveryNote.contains('지방배송(선결제)')) {
      deliveryColor = const Color(0xFF5B9BD5);
    } else if (deliveryNote.contains('시내배송(선결제)')) {
      deliveryColor = const Color(0xFFD6B18A);
    } else if (deliveryNote.contains('지방배송')) {
      deliveryColor = const Color(0xFFFFC000);
    } else if (deliveryNote.contains('시내배송')) {
      deliveryColor = const Color(0xFF92D050);
    }
    if (deliveryColor != null && inlandDeliveryText.trim().isNotEmpty) {
      c.drawRect(
        Rect.fromLTWH(leftW * .58 + 8, sumTop + 34, leftW * .42 - 16, layout.summaryHeight - 42),
        Paint()..color = deliveryColor.withOpacity(.32),
      );
    }
    _text(
      c,
      inlandDeliveryText,
      Rect.fromLTWH(leftW * .58 + 14, sumTop + 46, leftW * .42 - 24, layout.summaryHeight - 62),
      DocumentFormStyle.deliveryFontSize,
      bold: true,
      center: true,
      lineHeight: 1.16,
    );

    final totalX = leftW + 6;
    final totalW = w - totalX;
    _box(c, Rect.fromLTWH(totalX, sumTop, totalW, DocumentFormStyle.minimumSummaryHeight), totalColor);
    final adjH = 26.0;
    final lineDiscountPercent = freight.lines
        .map((line) => line.discountPercent)
        .fold<double>(0, (best, value) => value > best ? value : best);
    final discountPercentText = lineDiscountPercent > 0
        ? '${(lineDiscountPercent * 100).toStringAsFixed(
            ((lineDiscountPercent * 100) -
                        (lineDiscountPercent * 100).roundToDouble())
                    .abs() <
                .001
                ? 0
                : 2,
          )}%'
        : '';
    final discountGroupText = freight.lines
        .map((line) => line.discountGroup.trim())
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );
    final actualDiscountPercent = freight.lines
        .map((line) => line.discountPercent)
        .fold<double>(0, (best, value) => value > best ? value : best);
    final noteDiscountMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)%\s*적용')
        .firstMatch(displayAutoNotes);
    final noteDiscountPercent =
        double.tryParse(noteDiscountMatch?.group(1) ?? '') ?? 0;
    final actualDiscountPctText = actualDiscountPercent > 0
        ? '${pctText(actualDiscountPercent)}%'
        : (noteDiscountPercent > 0
            ? '${noteDiscountPercent.toStringAsFixed(
                (noteDiscountPercent - noteDiscountPercent.roundToDouble())
                            .abs() <
                        .001
                    ? 0
                    : 2,
              )}%'
            : '');
    final autoDiscountPercent = freight.lines
        .map((line) => line.autoDiscountPercent)
        .fold<double>(0, (best, value) => value > best ? value : best);
    final additionalDiscountPercent = freight.lines
        .map((line) => line.additionalDiscountPercent)
        .fold<double>(0, (best, value) => value > best ? value : best);
    final additionalDiscountName = freight.lines
        .map((line) => line.additionalDiscountName.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    String patch199Pct(double value) {
      if (value <= 0) return '';
      final p = value * 100;
      final digits = (p - p.roundToDouble()).abs() < .001 ? 0 : 2;
      return '${p.toStringAsFixed(digits)}%';
    }
    final autoDiscountPctText = patch199Pct(autoDiscountPercent);
    final additionalDiscountPctText = patch199Pct(additionalDiscountPercent);
    const discountLabel = '할인';
    final regularDiscountUsd = freight.lines.fold<double>(
          0, (sum, line) => sum + line.autoDiscountAmountUsd) +
        discountableExtraTotal * autoDiscountPercent;
    final specialDiscountUsd = freight.lines.fold<double>(
          0, (sum, line) => sum + line.additionalDiscountAmountUsd) +
        discountableExtraTotal * additionalDiscountPercent;

    // Three clear columns: label | percent (~2/3) | amount (far right).
    const adjustmentFont = 16.0;
    final adjustmentColumnLabelW = totalW * .46;
    final percentX = totalX + totalW * .54;
    final percentW = totalW * .18;
    final amountX = totalX + totalW * .74;
    final amountW = totalW * .22;

    _text(
      c,
      '운임 총합',
      Rect.fromLTWH(totalX + 12, sumTop + 3, adjustmentColumnLabelW, adjH),
      adjustmentFont,
      bold: true,
    );
    _text(
      c,
      MoneyFormat.usd(grossUsd),
      Rect.fromLTWH(amountX, sumTop + 3, amountW, adjH),
      adjustmentFont,
      bold: true,
      right: true,
    );

    _text(
      c,
      '할인',
      Rect.fromLTWH(totalX + 12, sumTop + 30, adjustmentColumnLabelW, adjH),
      adjustmentFont,
      bold: true,
    );
    _text(
      c,
      autoDiscountPctText.isNotEmpty
          ? autoDiscountPctText
          : '-',
      Rect.fromLTWH(percentX, sumTop + 30, percentW, adjH),
      adjustmentFont,
      bold: true,
      center: true,
    );
    _text(
      c,
      autoDiscountPctText.isNotEmpty
          ? '-${MoneyFormat.usd(regularDiscountUsd)}'
          : '-',
      Rect.fromLTWH(amountX, sumTop + 30, amountW, adjH),
      adjustmentFont,
      bold: true,
      right: true,
    );

    _text(
      c,
      additionalDiscountPctText.isNotEmpty
          ? (additionalDiscountName.isEmpty ? '추가 할인' : additionalDiscountName)
          : '',
      Rect.fromLTWH(totalX + 12, sumTop + 57, adjustmentColumnLabelW, adjH),
      adjustmentFont,
      bold: true,
    );
    _text(
      c,
      additionalDiscountPctText.isNotEmpty
          ? additionalDiscountPctText
          : '-',
      Rect.fromLTWH(percentX, sumTop + 57, percentW, adjH),
      adjustmentFont,
      bold: true,
      center: true,
    );
    _text(
      c,
      additionalDiscountPctText.isNotEmpty
          ? '-${MoneyFormat.usd(specialDiscountUsd)}'
          : '-',
      Rect.fromLTWH(amountX, sumTop + 57, amountW, adjH),
      adjustmentFont,
      bold: true,
      right: true,
    );

    _text(
      c,
      '세금 계산서(VAT)',
      Rect.fromLTWH(totalX + 12, sumTop + 84, adjustmentColumnLabelW, adjH),
      adjustmentFont,
      bold: true,
    );
    _text(
      c,
      '-',
      Rect.fromLTWH(percentX, sumTop + 84, percentW, adjH),
      adjustmentFont,
      bold: true,
      center: true,
    );
    _text(
      c,
      '-',
      Rect.fromLTWH(amountX, sumTop + 84, amountW, adjH),
      adjustmentFont,
      bold: true,
      right: true,
    );

    final finalTop = sumTop + 112;
    final labelW = totalW * .38;
    _box(c, Rect.fromLTWH(totalX, finalTop, labelW, 112), DocumentFormStyle.totalLabel);
    _text(c, '최종 명세서 총액', Rect.fromLTWH(totalX + 8, finalTop + 6, labelW - 16, 100),
        20, bold: true, center: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 0 * 28.0, totalW - labelW, 28.0),
        const Color(0xFFF3F7FC));
    _text(c, 'USD     ${MoneyFormat.usd(finalUsd)}',
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 0 * 28.0, totalW - labelW - 16, 28.0),
        21, bold: true, right: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 1 * 28.0, totalW - labelW, 28.0),
        const Color(0xFFEAF1F8));
    _text(c, 'KIP     ${MoneyFormat.kip(finalUsd * freight.rates.appliedKip)}',
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 1 * 28.0, totalW - labelW - 16, 28.0),
        21, bold: true, right: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 2 * 28.0, totalW - labelW, 28.0),
        const Color(0xFFF3F7FC));
    _text(c, 'THB     ${MoneyFormat.thb(finalUsd * freight.rates.appliedThb)}',
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 2 * 28.0, totalW - labelW - 16, 28.0),
        21, bold: true, right: true);
    _box(c, Rect.fromLTWH(totalX + labelW, finalTop + 3 * 28.0, totalW - labelW, 28.0),
        const Color(0xFFEAF1F8));
    _text(c, 'KRW     ${MoneyFormat.krw(finalUsd * freight.rates.appliedKrw)}',
        Rect.fromLTWH(totalX + labelW + 8, finalTop + 3 * 28.0, totalW - labelW - 16, 28.0),
        21, bold: true, right: true);
    final payTop = layout.paymentTop;
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
      lineHeight: 1.35,
    );

    final signTop = layout.signTop;
    final signW = w * .26;
    final signH = layout.signHeight;
    _box(c, Rect.fromLTWH(0, signTop, signW, signH), Colors.white);
    _box(c, Rect.fromLTWH(w - signW, signTop, signW, signH), Colors.white);
    _text(c, '엘케이 (LK)무역', Rect.fromLTWH(12, signTop + 8, signW - 24, 24),
        16, bold: true);
    _imageContain(c, stamp, Rect.fromLTWH(54, signTop + 4, signW - 62, 97));
    _text(
      c,
      docText.footerText,
      Rect.fromLTWH(signW + 18, signTop + 6, w - signW * 2 - 36, signH - 12),
      docText.footerFontSize,
      center: true,
      lineHeight: 1.2,
    );
    _text(c, '고객사 확인', Rect.fromLTWH(w - signW + 12, signTop + 8, signW - 24, 24),
        17, bold: true);

    c.drawRect(Offset.zero & size, border);
  }

  void _payment(Canvas c, ui.Image image, String title, String detail, Rect r) {
    _imageContain(c, image, Rect.fromLTWH(r.left + 6, r.top + 6, 132, 132));
    _text(c, title, Rect.fromLTWH(r.left + 144, r.top + 8, r.width - 150, 32), 22, bold: true, center: true);
    _text(c, detail, Rect.fromLTWH(r.left + 144, r.top + 42, r.width - 150, 96),
        22, bold: true, center: true);
  }

  void _kv(Canvas c, String k, String v, Rect r, {bool emphasize = false}) {
    const labelW = 165.0;
    _text(
      c,
      k,
      Rect.fromLTWH(r.left, r.top, labelW, r.height),
      18,
      bold: true,
      center: true,
    );
    _text(
      c,
      v.isEmpty ? '-' : v,
      Rect.fromLTWH(r.left + labelW, r.top, r.width - labelW, r.height),
      emphasize ? 22 : 20,
      bold: emphasize,
      center: true,
    );
  }

  void _labelValue(Canvas c, String label, String value, Rect r,
      {double valueSize = 30}) {
    _box(c, r, paleBlue);
    _text(c, label, Rect.fromLTWH(r.left, r.top + 4, r.width, 22),
        16, bold: true, center: true);
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
      {bool bold = false, bool center = false, bool right = false, double lineHeight = 1.15}) {
    DocumentFormStyle.drawText(c, text, r, size,
        bold: bold, center: center, right: right, lineHeight: lineHeight);
  }

  @override
  bool shouldRepaint(covariant _DigitalStatementPainter oldDelegate) => true;
}










class StatementRenderRequest {
  const StatementRenderRequest({
    required this.routeLabel,
    required this.year,
    required this.voyage,
    required this.receiptNumber,
  });

  final String routeLabel;
  final int year;
  final String voyage;
  final String receiptNumber;
}

class StatementDocumentRenderer {
  StatementDocumentRenderer._();

  static Future<ui.Image> _asset(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<({Uint8List bytes, double width, double height})> _renderOne(
    StatementRenderRequest request,
    List<ui.Image> assets,
  ) async {
    final rows = await StatementService.instance.rowsForReceipt(
      route: request.routeLabel,
      year: request.year,
      voyage: request.voyage,
      receiptNumber: request.receiptNumber,
    );
    if (rows.isEmpty) {
      throw StateError('${request.receiptNumber}: 명세서 데이터가 없습니다.');
    }
    final freight = await FreightService.instance.calculate(rows);
    final inland = await CustomerBenefitService.instance
        .inlandTextForRows(request.routeLabel, rows);
    final extraCosts = await ReceiptExtraCostService.instance.list(
      route: request.routeLabel,
      year: request.year,
      voyage: request.voyage,
      receiptNumber: request.receiptNumber,
    );
    const docWidth = DocumentFormStyle.width;
    // 1440px wide JPEG is clear for an A4 half-page while using a fraction of
    // the heap required by the previous 2430px PNG.
    const scale = .8;

    final painter = _DigitalStatementPainter(
      routeLabel: request.routeLabel,
      rows: rows,
      freight: freight,
      receiptNumber: request.receiptNumber,
      voyage: request.voyage,
      inlandDeliveryText: inland,
      extraCosts: extraCosts,
      logo: assets[0],
      qrUsd: assets[1],
      qrKip: assets[2],
      qrThb: assets[3],
      stamp: assets[4],
      bankStrip: assets[5],
    );
    final docHeight = painter.documentHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    painter.paint(canvas, Size(docWidth, docHeight));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (docWidth * scale).round(),
      (docHeight * scale).round(),
    );
    picture.dispose();
    try {
      final bytes = await _encodeJpeg(image, quality: 84);
      return (bytes: bytes, width: docWidth, height: docHeight);
    } finally {
      image.dispose();
    }
  }

  static Future<Uint8List> renderBatchPdf(
    List<StatementRenderRequest> requests,
  ) async {
    if (requests.isEmpty) throw ArgumentError('출력할 명세서가 없습니다.');
    final assets = await Future.wait<ui.Image>([
      _asset('assets/images/company_logo_transparent.png'),
      _asset('assets/images/payment_qr_usd.png'),
      _asset('assets/images/payment_qr_kip.png'),
      _asset('assets/images/payment_qr_thb.png'),
      _asset('assets/images/company_stamp.png'),
      _asset('assets/images/bank_accounts_strip.png'),
    ]);
    try {
      final batch = StatementPdfBatchBuilder();
      for (final request in requests) {
        final rendered = await _renderOne(request, assets);
        batch.addStatement(
          rendered.bytes,
          sourceWidth: rendered.width,
          sourceHeight: rendered.height,
        );
      }
      return batch.save();
    } finally {
      for (final image in assets) {
        image.dispose();
      }
    }
  }
}


