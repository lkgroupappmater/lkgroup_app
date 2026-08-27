import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../config/supabase_config.dart';
import '../services/schedule_service.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key});
  @override State<ScheduleManagementScreen> createState() => _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (SupabaseConfig.isConfigured) {
      try { _items.addAll(await ScheduleService.instance.list()); } catch (e) { _message('일정 조회 실패: $e'); }
    }
    if (_items.isEmpty) {
      _items.addAll([
        {'route': '한국->라오스 해상', 'year': '2026년', 'voyage': '01항차', 'origin': '부산항', 'destination': '비엔티안', 'booking_close_date': '2026-07-05', 'estimated_arrival_date': '2026-08-01', 'detail': '선적 서류는 마감일 전까지 제출해 주세요.'},
        {'route': '한국->라오스 항공', 'year': '2026년', 'voyage': '02항차', 'origin': '인천공항', 'destination': '와타이공항', 'booking_close_date': '2026-07-10', 'estimated_arrival_date': '2026-07-12', 'detail': '항공 화물 접수 일정입니다.'},
      ]);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _edit(int index) => _showEditor(existing: _items[index], index: index);
  Future<void> _delete(int index) async {
    final id = _items[index]['id'];
    try { if (id is int) await ScheduleService.instance.delete(id); _items.removeAt(index); if (mounted) setState(() {}); _message('선적 일정이 삭제되었습니다.'); }
    catch (e) { _message('삭제 실패: $e'); }
  }

  void _showEditor({Map<String, dynamic>? existing, int? index}) {
    final from = TextEditingController(text: '${existing?['origin'] ?? ''}');
    final to = TextEditingController(text: '${existing?['destination'] ?? ''}');
    final close = TextEditingController(text: '${existing?['booking_close_date'] ?? ''}');
    final eta = TextEditingController(text: '${existing?['estimated_arrival_date'] ?? ''}');
    final detail = TextEditingController(text: '${existing?['detail'] ?? ''}');
    var route = '${existing?['route'] ?? RouteCatalog.routes.first}';
    var year = '${existing?['year'] ?? '2026년'}';
    var voyage = '${existing?['voyage'] ?? '01항차'}';
    showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(existing == null ? '선적 일정 추가' : '선적 일정 편집'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: route, decoration: const InputDecoration(labelText: '운송 경로'), items: RouteCatalog.routes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setDialogState(() => route = v ?? route)),
        DropdownButtonFormField<String>(value: year, decoration: const InputDecoration(labelText: '년도'), items: const ['2026년','2027년','2028년'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setDialogState(() => year = v ?? year)),
        DropdownButtonFormField<String>(value: voyage, decoration: const InputDecoration(labelText: '항차'), items: const ['01항차','02항차','03항차','04항차','05항차'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setDialogState(() => voyage = v ?? voyage)),
        TextField(controller: from, decoration: const InputDecoration(labelText: '출발지')), TextField(controller: to, decoration: const InputDecoration(labelText: '도착지')), TextField(controller: close, decoration: const InputDecoration(labelText: '접수 마감일')), TextField(controller: eta, decoration: const InputDecoration(labelText: '도착 예정일')), TextField(controller: detail, maxLines: 3, decoration: const InputDecoration(labelText: '상세 내용 또는 추가 내용')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')), FilledButton(onPressed: () async {
        final item = <String, dynamic>{'route': route, 'year': year, 'voyage': voyage, 'origin': from.text.trim(), 'destination': to.text.trim(), 'booking_close_date': close.text.trim().isEmpty ? null : close.text.trim(), 'estimated_arrival_date': eta.text.trim().isEmpty ? null : eta.text.trim(), 'detail': detail.text.trim(), 'status': 'scheduled'};
        try { await ScheduleService.instance.save(item, id: existing?['id'] is int ? existing!['id'] as int : null); if (index == null) { _items.add(item); } else { item['id'] = existing?['id']; _items[index] = item; } if (mounted) setState(() {}); Navigator.pop(dialogContext); } catch (e) { _message('저장 실패: $e'); }
      }, child: const Text('저장'))],
    ))).whenComplete(() { from.dispose(); to.dispose(); close.dispose(); eta.dispose(); detail.dispose(); });
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('선적 일정 목록 관리'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white), backgroundColor: AppColors.background,
    body: _loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _items.length + 1, itemBuilder: (context, index) {
      if (index == _items.length) return Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.icon(onPressed: () => _showEditor(), icon: const Icon(Icons.add), label: const Text('선적 일정 추가')));
      final item = _items[index];
      return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('${item['route']} · ${item['voyage']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary))), IconButton(onPressed: () => _edit(index), icon: const Icon(Icons.edit_outlined)), IconButton(onPressed: () => _delete(index), icon: const Icon(Icons.delete_outline, color: AppColors.error))]),
        Text('${item['year']} | ${item['origin']} → ${item['destination']}'), const SizedBox(height: 6), Text('접수 마감 ${item['booking_close_date'] ?? '-'} · 도착 예정 ${item['estimated_arrival_date'] ?? '-'}', style: const TextStyle(color: AppColors.textSecondary)), if ('${item['detail'] ?? ''}'.isNotEmpty) ...[const SizedBox(height: 8), Text('${item['detail']}', style: const TextStyle(color: AppColors.textSecondary))],
      ])));
    }),
  );
}
