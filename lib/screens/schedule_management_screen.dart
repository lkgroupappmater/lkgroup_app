import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../services/content_service.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key});
  @override
  State<ScheduleManagementScreen> createState() => _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final rows = await ContentService.fetchSchedules(includePendingDeletion: true); if (mounted) setState(() { _items = rows; _loading = false; }); }
    catch (e) { if (mounted) { setState(() => _loading = false); _message('선적 일정 조회 실패: $e'); } }
  }
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  String _text(Map<String, dynamic> row, String key) => (row[key] ?? '').toString();

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = _text(row, 'id');
    if (id.isEmpty) return;
    try { await ContentService.requestScheduleDeletion(id); _message('삭제 대기중으로 변경했습니다. 30일 후 자동 삭제됩니다.'); await _load(); }
    catch (e) { _message('삭제 요청 실패: $e'); }
  }

  Future<void> _showEditor({Map<String, dynamic>? existing}) async {
    final from = TextEditingController(text: _text(existing ?? {}, 'origin'));
    final to = TextEditingController(text: _text(existing ?? {}, 'destination'));
    final close = TextEditingController(text: _text(existing ?? {}, 'closing_date'));
    final eta = TextEditingController(text: _text(existing ?? {}, 'arrival_date'));
    final detail = TextEditingController(text: _text(existing ?? {}, 'detail'));
    String route = _text(existing ?? {}, 'route').isEmpty ? RouteCatalog.routes.first : _text(existing ?? {}, 'route');
    if (!RouteCatalog.routes.contains(route)) route = RouteCatalog.routes.first;
    try {
      await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(existing == null ? '선적 일정 추가' : '선적 일정 편집'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: route, decoration: const InputDecoration(labelText: '운송 경로'), items: RouteCatalog.routes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setDialogState(() => route = v ?? route)),
          TextField(controller: from, decoration: const InputDecoration(labelText: '출발지')),
          TextField(controller: to, decoration: const InputDecoration(labelText: '도착지')),
          TextField(controller: close, decoration: const InputDecoration(labelText: '접수 마감일 (YYYY-MM-DD)')),
          TextField(controller: eta, decoration: const InputDecoration(labelText: '도착 예정일 (YYYY-MM-DD)')),
          TextField(controller: detail, maxLines: 3, decoration: const InputDecoration(labelText: '상세 내용')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')), FilledButton(onPressed: () async {
          final data = <String, dynamic>{'route': route, 'origin': from.text.trim(), 'destination': to.text.trim(), 'closing_date': close.text.trim(), 'arrival_date': eta.text.trim(), 'detail': detail.text.trim()};
          try { if (existing == null) { await ContentService.createSchedule(data); } else { await ContentService.updateSchedule(_text(existing, 'id'), data); } if (dialogContext.mounted) Navigator.pop(dialogContext); await _load(); }
          catch (e) { _message('저장 실패: $e'); }
        }, child: const Text('저장'))],
      )));
    } finally { from.dispose(); to.dispose(); close.dispose(); eta.dispose(); detail.dispose(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('선적 일정 목록 관리'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white), backgroundColor: AppColors.background,
    body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      ..._items.map((row) { final pending = _text(row, 'deletion_status') == 'pending'; return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(_text(row, 'route'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary))), if (pending) const Chip(label: Text('삭제 대기중')), IconButton(onPressed: pending ? null : () => _showEditor(existing: row), icon: const Icon(Icons.edit_outlined)), IconButton(onPressed: pending ? null : () => _delete(row), icon: const Icon(Icons.delete_outline, color: AppColors.error))]),
        Text('${_text(row, 'origin')} → ${_text(row, 'destination')}'), const SizedBox(height: 6), Text('마감 ${_text(row, 'closing_date')} · 도착 ${_text(row, 'arrival_date')}', style: const TextStyle(color: AppColors.textSecondary)), if (_text(row, 'detail').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_text(row, 'detail'))),
      ]))); }),
      FilledButton.icon(onPressed: () => _showEditor(), icon: const Icon(Icons.add), label: const Text('선적 일정 추가')),
    ])),
  );
}

