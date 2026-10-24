import 'package:flutter/material.dart';
import '../core/cargo_note_colors.dart';
import '../services/cargo_note_palette_service.dart';

/// Color belongs to the remark only. The original controller and data are retained.
class DeliveryNoteHighlight extends StatefulWidget {
  const DeliveryNoteHighlight({super.key, required this.row, required this.child, this.loadColors})
      : controller = null, decoration = const InputDecoration(), maxLines = 1;
  const DeliveryNoteHighlight.field({super.key, required this.row, required this.controller,
    required this.decoration, this.maxLines = 1, this.loadColors}) : child = null;
  final Map<String, dynamic> row;
  final Widget? child;
  final TextEditingController? controller;
  final InputDecoration decoration;
  final int maxLines;
  final Future<Map<String, String>> Function(Map<String, dynamic>)? loadColors;
  @override
  State<DeliveryNoteHighlight> createState() => _DeliveryNoteHighlightState();
}
class _DeliveryNoteHighlightState extends State<DeliveryNoteHighlight> {
  late Future<Map<String, String>> _colors;
  String _kind = '';
  void _changed() { final kind = CargoNoteColors.kind(_row); if (kind != _kind) setState(_load); }
  Map<String, dynamic> get _row => {...widget.row, if (widget.controller != null) 'notes': widget.controller!.text};
  void _load() { _kind = CargoNoteColors.kind(_row); _colors = (widget.loadColors ?? CargoNotePaletteService.instance.colors)(_row); }
  @override
  void initState() { super.initState(); widget.controller?.addListener(_changed); _load(); }
  @override
  void didUpdateWidget(covariant DeliveryNoteHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) { oldWidget.controller?.removeListener(_changed); widget.controller?.addListener(_changed); }
    if (!identical(oldWidget.row, widget.row) || oldWidget.loadColors != widget.loadColors) _load();
  }
  @override
  void dispose() { widget.controller?.removeListener(_changed); super.dispose(); }
  Widget _build(Map<String, String> palette) {
    final color = CargoNoteColors.color(_row, palette);
    if (widget.controller != null) return TextField(controller: widget.controller, maxLines: widget.maxLines,
      style: color == null ? null : TextStyle(color: CargoNoteColors.ink(color)),
      decoration: color == null ? widget.decoration : widget.decoration.copyWith(filled: true, fillColor: color));
    if (color == null) return widget.child!;
    return Container(color: color, padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: DefaultTextStyle.merge(style: TextStyle(color: CargoNoteColors.ink(color)), child: widget.child!));
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>>(future: _colors,
    builder: (context, snapshot) => widget.controller == null ? _build(snapshot.data ?? CargoNoteColors.defaults)
      : ValueListenableBuilder<TextEditingValue>(valueListenable: widget.controller!,
          builder: (context, value, child) => _build(snapshot.data ?? CargoNoteColors.defaults)));
}
