import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class NoticeManagementScreen extends StatefulWidget {
  const NoticeManagementScreen({super.key});

  @override
  State<NoticeManagementScreen> createState() => _NoticeManagementScreenState();
}

class _NoticeManagementScreenState extends State<NoticeManagementScreen> {
  final List<Map<String, String>> _items = [
    {'title': '2025년 하반기 운임 조정 안내', 'date': '2025-07-01', 'content': '하반기 운임 변경 내용을 확인해 주세요.'},
    {'title': '통관 서류 제출 기한 변경 안내', 'date': '2025-06-20', 'content': '통관 서류 제출 기한이 변경되었습니다.'},
  ];

  void _edit(int index) => _showEditor(existing: _items[index], index: index);

  void _delete(int index) {
    setState(() => _items.removeAt(index));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공지사항이 삭제되었습니다.')));
  }

  void _showEditor({Map<String, String>? existing, int? index}) {
    final title = TextEditingController(text: existing?['title'] ?? '');
    final content = TextEditingController(text: existing?['content'] ?? '');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? '공지사항 추가' : '공지사항 편집'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: '제목')),
            TextField(controller: content, maxLines: 5, decoration: const InputDecoration(labelText: '내용')),
            const SizedBox(height: 8),
            const Align(alignment: Alignment.centerLeft, child: Text('등록 날짜는 저장 시 자동으로 입력됩니다.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              final item = <String, String>{
                'title': title.text.trim(),
                'date': existing?['date'] ?? DateTime.now().toIso8601String().substring(0, 10),
                'content': content.text.trim(),
              };
              if (item['title']!.isEmpty || item['content']!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제목과 내용을 입력해 주세요.')));
                return;
              }
              setState(() {
                if (index == null) {
                  _items.add(item);
                } else {
                  _items[index] = item;
                }
              });
              Navigator.pop(dialogContext);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    ).whenComplete(() {
      title.dispose();
      content.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('공지사항 목록 관리'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white),
      backgroundColor: AppColors.background,
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.icon(onPressed: () => _showEditor(), icon: const Icon(Icons.add), label: const Text('공지사항 추가')));
          }
          final item = _items[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(item['title'] ?? ''),
              subtitle: Text('${item['date']}\n${item['content']}'),
              isThreeLine: true,
              trailing: Wrap(children: [
                IconButton(onPressed: () => _edit(index), icon: const Icon(Icons.edit_outlined)),
                IconButton(onPressed: () => _delete(index), icon: const Icon(Icons.delete_outline, color: AppColors.error)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
