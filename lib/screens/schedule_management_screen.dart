import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key});
  @override State<ScheduleManagementScreen> createState() => _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  final List<Map<String, String>> _items = [
    {'route': '한국-라오스 해상', 'year': '2026년', 'voyage': '01항차', 'from': '부산항', 'to': '비엔티안', 'close': '2026-07-05', 'eta': '2026-08-01'},
    {'route': '한국-라오스 항공', 'year': '2026년', 'voyage': '02항차', 'from': '인천공항', 'to': '와타이공항', 'close': '2026-07-10', 'eta': '2026-07-12'},
    {'route': '라오스-태국 육로', 'year': '2026년', 'voyage': '01항차', 'from': '비엔티안', 'to': '방콕', 'close': '2026-07-15', 'eta': '2026-07-18'},
  ];
  void _edit(int i) => _showEditor(existing: _items[i], index: i);
  void _delete(int i) { setState(() => _items.removeAt(i)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('선적 일정이 삭제되었습니다.'))); }
  void _showEditor({Map<String, String>? existing, int? index}) {
    final from = TextEditingController(text: existing?['from'] ?? ''), to = TextEditingController(text: existing?['to'] ?? ''), close = TextEditingController(text: existing?['close'] ?? ''), eta = TextEditingController(text: existing?['eta'] ?? '');
    String route = existing?['route'] ?? routeLabels.first, year = existing?['year'] ?? '2026년', voyage = existing?['voyage'] ?? '01항차';
    showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(title: Text(existing == null ? '선적 일정 추가' : '선적 일정 편집'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(value: route, decoration: const InputDecoration(labelText: '운송 경로'), items: routeLabels.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setDialogState(() => route = v ?? route)),
      DropdownButtonFormField<String>(value: year, decoration: const InputDecoration(labelText: '년도'), items: const ['2026년', '2027년', '2028년'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setDialogState(() => year = v ?? year)),
      DropdownButtonFormField<String>(value: voyage, decoration: const InputDecoration(labelText: '항차'), items: ['01항차', '02항차', '03항차', '04항차', '05항차'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setDialogState(() => voyage = v ?? voyage)),
      TextField(controller: from, decoration: const InputDecoration(labelText: '출발지')), TextField(controller: to, decoration: const InputDecoration(labelText: '도착지')), TextField(controller: close, decoration: const InputDecoration(labelText: '접수 마감일')), TextField(controller: eta, decoration: const InputDecoration(labelText: '도착 예정일')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')), FilledButton(onPressed: () { final item = {'route': route, 'year': year, 'voyage': voyage, 'from': from.text, 'to': to.text, 'close': close.text, 'eta': eta.text}; setState(() { if (index == null) { _items.add(item); } else { _items[index!] = item; } }); Navigator.pop(dialogContext); }, child: const Text('저장'))])));
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('선적 일정 목록 관리'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white), backgroundColor: AppColors.background, body: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _items.length + 1, itemBuilder: (context, index) {
    if (index == _items.length) return Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.icon(onPressed: () => _showEditor(), icon: const Icon(Icons.add), label: const Text('선적 일정 추가')));
    final item = _items[index]; return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text('${item['route']} · ${item['voyage']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary))), IconButton(onPressed: () => _edit(index), icon: const Icon(Icons.edit_outlined)), IconButton(onPressed: () => _delete(index), icon: const Icon(Icons.delete_outline, color: AppColors.error))]), Text('${item['year']}  |  ${item['from']} → ${item['to']}'), const SizedBox(height: 6), Text('접수 마감 ${item['close']}  ·  도착 예정 ${item['eta']}', style: const TextStyle(color: AppColors.textSecondary))])));
  });
}
