import 'package:flutter/material.dart';

/// Client-side filtering over the currently authorized list; does not change stored data.
class ManagementFieldFilter {
  String field = '', query = '';
  Iterable<dynamic> _values(dynamic node, String key) sync* {
    if (node is Map) { if (node.containsKey(key)) yield node[key]; for (final value in node.values) { if (value is Map || value is List) yield* _values(value, key); } }
    if (node is List) { for (final value in node) { yield* _values(value, key); } }
  }
  bool matches(Map<String, dynamic> row) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final values = field.isEmpty ? row.values : _values(row, field);
    return values.any((value) {
      final text = '${value ?? ''}'.toLowerCase();
      if (field == 'customer_code' && RegExp(r'^(?:id\s*[:#-]?\s*)?\d+$').hasMatch(q)) {
        final digits = q.replaceAll(RegExp(r'\D'), '');
        return int.tryParse(text) == int.tryParse(digits);
      }
      return text.contains(q) || (field.contains('phone') && text.replaceAll(RegExp(r'\D'), '').contains(q.replaceAll(RegExp(r'\D'), '')) && q.replaceAll(RegExp(r'\D'), '').isNotEmpty);
    });
  }
}

class ManagementFieldSearch extends StatefulWidget implements PreferredSizeWidget {
  const ManagementFieldSearch({super.key, required this.filter, required this.fields, required this.onChanged});
  final ManagementFieldFilter filter;
  final Map<String, String> fields;
  final VoidCallback onChanged;
  @override
  Size get preferredSize => const Size.fromHeight(112);
  @override
  State<ManagementFieldSearch> createState() => _ManagementFieldSearchState();
}
class _ManagementFieldSearchState extends State<ManagementFieldSearch> {
  late final _text = TextEditingController(text: widget.filter.query);
  @override
  void dispose() { _text.dispose(); super.dispose(); }
  void _search() { widget.filter.query = _text.text; widget.onChanged(); }
  @override
  Widget build(BuildContext context) => Material(color: Theme.of(context).colorScheme.surface, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Row(children: [
      Expanded(child: DropdownButton<String>(isExpanded: true, value: widget.filter.field, items: [const DropdownMenuItem(value: '', child: Text('전체 항목')), ...widget.fields.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))], onChanged: (v) { if (v != null) { widget.filter.field = v; _search(); } })),
      TextButton(onPressed: () { _text.clear(); widget.filter.field = ''; _search(); }, child: const Text('초기화')),
    ]),
    Row(children: [Expanded(child: TextField(controller: _text, decoration: const InputDecoration(hintText: '항목별 검색', isDense: true, border: OutlineInputBorder()), textInputAction: TextInputAction.search, onSubmitted: (_) => _search())), const SizedBox(width: 8), TextButton(onPressed: _search, child: const Text('검색'))]),
  ])));
}
