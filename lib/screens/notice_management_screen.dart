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

  String _text(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString();

  String _dateOnly(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '';
    return text.contains('T') ? text.split('T').first : text.split(' ').first;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    try {
      final rows = await ContentService.fetchNotices(includePendingDeletion: true);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('공지사항 조회 실패: $e');
    }
  }

  Future<void> _requestDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('공지사항 삭제 확인'),
        content: const Text(
          '삭제하면 홈 화면에서는 즉시 보이지 않습니다.\n'
          '삭제된 자료는 30일 동안 임시 보관 후 완전히 삭제됩니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('확인')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ContentService.requestNoticeDeletion(_text(row, 'id'));
      _message('삭제 대기중으로 변경했습니다. 30일 후 완전히 삭제됩니다.');
      await _load();
    } catch (e) {
      _message('삭제 요청 실패: $e');
    }
  }

  Future<void> _hardDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('바로 삭제'),
        content: const Text('임시 보관 기간을 무시하고 DB에서 완전히 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('바로 삭제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ContentService.hardDeleteNotice(_text(row, 'id'));
      _message('공지사항을 완전히 삭제했습니다.');
      await _load();
    } catch (e) {
      _message('바로 삭제 실패: $e');
    }
  }

  Future<void> _restore(Map<String, dynamic> row) async {
    try {
      await ContentService.restoreNotice(_text(row, 'id'));
      _message('삭제를 취소했습니다. 홈 화면에 다시 표시됩니다.');
      await _load();
    } catch (e) {
      _message('삭제 취소 실패: $e');
    }
  }

  Future<void> _showEditor({Map<String, dynamic>? existing}) async {
    final title = TextEditingController(text: _text(existing ?? {}, 'title'));
    final content = TextEditingController(text: _text(existing ?? {}, 'content'));
    bool pinned = existing?['is_pinned'] == true;
    bool showPublishedDate = existing == null || existing['show_published_date'] != false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '공지사항 추가' : '공지사항 편집'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    hintText: '예: 9월 한국→라오스 해상 일정 안내',
                  ),
                ),
                TextField(
                  controller: content,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    hintText: '공지 내용을 입력해 주세요.',
                  ),
                ),
                CheckboxListTile(
                  value: showPublishedDate,
                  onChanged: (v) => setDialogState(() => showPublishedDate = v ?? true),
                  title: const Text('등록 날짜 표시'),
                ),
                CheckboxListTile(
                  value: pinned,
                  onChanged: (v) => setDialogState(() => pinned = v ?? false),
                  title: const Text('상단 고정'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || content.text.trim().isEmpty) {
                  _message('제목과 내용을 입력해 주세요.');
                  return;
                }
                final data = <String, dynamic>{
                  'title': title.text.trim(),
                  'content': content.text.trim(),
                  'is_pinned': pinned,
                  'show_published_date': showPublishedDate,
                  'published_at': DateTime.now().toUtc().toIso8601String(),
                };
                try {
                  if (existing == null) {
                    await ContentService.createNotice(data);
                  } else {
                    await ContentService.updateNotice(_text(existing, 'id'), data);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (e) {
                  _message('${existing == null ? '작성' : '저장'} 실패: $e');
                }
              },
              child: Text(existing == null ? '작성' : '저장'),
            ),
          ],
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    content.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.role.canEditNotices) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('공지사항 관리'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('공지사항 목록 관리'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
      ),
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: const Text('공지 추가'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_items.isEmpty)
                    const Card(child: ListTile(title: Text('등록된 공지사항이 없습니다.'))),
                  ..._items.map((row) {
                    final pending = _text(row, 'deletion_status') == 'pending';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            _text(row, 'title'),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (pending)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Chip(label: Text('삭제 대기중')),
                                        )
                                      else ...[
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 40,
                                            minHeight: 40,
                                          ),
                                          onPressed: () => _showEditor(existing: row),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 40,
                                            minHeight: 40,
                                          ),
                                          onPressed: () => _requestDelete(row),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: AppColors.error,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (row['show_published_date'] != false) ...[
                                    Text(
                                      _dateOnly(row['published_at']),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppColors.textSecondary),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Text(
                                    _text(row, 'content'),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            if (pending)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _restore(row),
                                      child: const Text('삭제 취소'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => _hardDelete(row),
                                      child: const Text('바로 삭제'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
