import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';
import '../services/content_service.dart';

class NoticeManagementScreen extends StatefulWidget {
  const NoticeManagementScreen({super.key, required this.user});
  final AppUser user;
  @override
  State<NoticeManagementScreen> createState() => _NoticeManagementScreenState();
}

class _NoticeManagementScreenState extends State<NoticeManagementScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    if (widget.user.role.canEditNotices) {
      _load();
    } else {
      _loading = false;
    }
  }
  String _text(Map<String, dynamic> row, String key) => (row[key] ?? '').toString();
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _load() async { try { final rows = await ContentService.fetchNotices(includePendingDeletion: true); if (mounted) setState(() { _items = rows; _loading = false; }); } catch (e) { if (mounted) { setState(() => _loading = false); _message('공지사항 조회 실패: $e'); } } }
  Future<void> _delete(Map<String, dynamic> row) async { try { await ContentService.requestNoticeDeletion(_text(row, 'id')); _message('삭제 대기중으로 변경했습니다. 30일 후 자동 삭제됩니다.'); await _load(); } catch (e) { _message('삭제 요청 실패: $e'); } }
  Future<void> _showEditor({Map<String, dynamic>? existing}) async {
    final title = TextEditingController(text: _text(existing ?? {}, 'title'));
    final content = TextEditingController(text: _text(existing ?? {}, 'content'));
    bool pinned = existing?['is_pinned'] == true;
    try { await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(existing == null ? '공지사항 추가' : '공지사항 편집'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, decoration: const InputDecoration(labelText: '제목')), TextField(controller: content, maxLines: 5, decoration: const InputDecoration(labelText: '내용')), CheckboxListTile(value: pinned, onChanged: (v) => setDialogState(() => pinned = v ?? false), title: const Text('상단 고정'))])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')), FilledButton(onPressed: () async { if (title.text.trim().isEmpty || content.text.trim().isEmpty) { _message('제목과 내용을 입력해 주세요.'); return; } final data = <String, dynamic>{'title': title.text.trim(), 'content': content.text.trim(), 'is_pinned': pinned, 'published_at': DateTime.now().toUtc().toIso8601String()}; try { if (existing == null) { await ContentService.createNotice(data); } else { await ContentService.updateNotice(_text(existing, 'id'), data); } if (dialogContext.mounted) Navigator.pop(dialogContext); await _load(); } catch (e) { _message('저장 실패: $e'); } }, child: const Text('저장'))],
    ))); } finally { title.dispose(); content.dispose(); }
  }
  @override
  Widget build(BuildContext context) {
    if (!widget.user.role.canEditNotices) {
      return Scaffold(
        appBar: AppBar(title: const Text('공지사항 관리'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white),
        body: const Center(child: Text('관리자 권한이 필요합니다.')),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('공지사항 목록 관리'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white), backgroundColor: AppColors.background, body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
    ..._items.map((row) { final pending = _text(row, 'deletion_status') == 'pending'; return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(title: Text(_text(row, 'title')), subtitle: Text('${_text(row, 'published_at')}\n${_text(row, 'content')}'), isThreeLine: true, trailing: Wrap(children: [if (pending) const Chip(label: Text('삭제 대기중')), IconButton(onPressed: pending ? null : () => _showEditor(existing: row), icon: const Icon(Icons.edit_outlined)), IconButton(onPressed: pending ? null : () => _delete(row), icon: const Icon(Icons.delete_outline, color: AppColors.error))]))); }),
    FilledButton.icon(onPressed: () => _showEditor(), icon: const Icon(Icons.add), label: const Text('공지사항 추가')),
  ])));
  }
}


