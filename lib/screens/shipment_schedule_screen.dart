import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/content_service.dart';

class ShipmentScheduleScreen extends StatefulWidget {
  const ShipmentScheduleScreen({super.key});
  @override
  State<ShipmentScheduleScreen> createState() => _ShipmentScheduleScreenState();
}
class _ShipmentScheduleScreenState extends State<ShipmentScheduleScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() { super.initState(); _future = ContentService.fetchSchedules(); }
  String _v(Map<String, dynamic> r, String k) => (r[k] ?? '').toString();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('선적 일정'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white), backgroundColor: AppColors.background, body: FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: Text('선적 일정 조회 실패\n${snapshot.error}'));
    final rows = snapshot.data ?? <Map<String, dynamic>>[];
    if (rows.isEmpty) return const Center(child: Text('등록된 선적 일정이 없습니다.'));
    return RefreshIndicator(onRefresh: () async => setState(() => _future = ContentService.fetchSchedules()), child: ListView(padding: const EdgeInsets.all(16), children: rows.map((r) => Card(margin: const EdgeInsets.only(bottom: 10), child: ExpansionTile(title: Text(_v(r, 'route'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)), subtitle: Text('${_v(r, 'origin')} → ${_v(r, 'destination')}'), childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14), children: [Align(alignment: Alignment.centerLeft, child: Text('접수 마감: ${_v(r, 'closing_date')}\n도착 예정: ${_v(r, 'arrival_date')}\n\n${_v(r, 'detail')}'))]))).toList()));
  }));
}

