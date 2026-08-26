import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/content_service.dart';

class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({super.key});
  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = ContentService.fetchNotices();
  }

  String _v(Map<String, dynamic> row, String key) => (row[key] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('공지사항'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white),
      backgroundColor: AppColors.background,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('공지사항 조회 실패\n${snapshot.error}'));
          final rows = snapshot.data ?? <Map<String, dynamic>>[];
          if (rows.isEmpty) return const Center(child: Text('등록된 공지사항이 없습니다.'));
          return RefreshIndicator(
            onRefresh: () async { setState(() => _future = ContentService.fetchNotices()); await _future; },
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final notice = rows[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
                  child: ExpansionTile(
                    title: Text(_v(notice, 'title'), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    subtitle: Text(_v(notice, 'published_at'), style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    children: <Widget>[
                      const Divider(),
                      Align(alignment: Alignment.centerLeft, child: Text(_v(notice, 'content'), style: const TextStyle(height: 1.6, color: AppColors.textSecondary))),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

