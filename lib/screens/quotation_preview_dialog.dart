import 'dart:typed_data';

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
  bool _saving = false;
  final TransformationController _transform = TransformationController();

  String get _routeKey => RouteCatalog.keyFor(widget.routeLabel);
  String get _assetPath => 'assets/quotation_forms/${_routeKey.toLowerCase()}.png';

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.8, 5.0);
    _transform.value = Matrix4.identity()..scale(target);
  }

  void _resetZoom() {
    _transform.value = Matrix4.identity();
  }

  Future<void> _savePng() async {
    setState(() => _saving = true);
    try {
      final data = await rootBundle.load(_assetPath);
      final Uint8List bytes = data.buffer.asUint8List();

      final now = DateTime.now();
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final fileName =
          '${prefix.isEmpty ? 'QUOTATION' : prefix}_QUOTATION_FORM_${now.year}${_two(now.month)}${_two(now.day)}.png';

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
            uri == null ? '이미지 저장을 취소했습니다.' : '견적서 이미지를 저장했습니다.',
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return InteractiveViewer(
                      transformationController: _transform,
                      panEnabled: true,
                      scaleEnabled: true,
                      minScale: 0.8,
                      maxScale: 5.0,
                      boundaryMargin: const EdgeInsets.all(220),
                      clipBehavior: Clip.none,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: Center(
                          child: Image.asset(
                            _assetPath,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, error, __) => Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                '견적서 원본 이미지 로딩 실패\n$_assetPath\n$error',
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
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
                      onPressed: _saving ? null : _savePng,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      label: const Text('이미지 저장'),
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
