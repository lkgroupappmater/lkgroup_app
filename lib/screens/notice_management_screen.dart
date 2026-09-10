import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/ui_localizations.dart';
import '../models/app_user.dart';
import '../services/content_service.dart';
import '../widgets/content_media.dart';

class NoticeManagementScreen extends StatefulWidget {
  const NoticeManagementScreen({
    super.key,
    required this.user,
    this.language = AppLanguage.korean,
  });
  final AppUser user;
  final AppLanguage language;

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
  String _u(String korean) => UiLocalizations.get(widget.language, korean);
  String _ue(String prefix, Object error) =>
      UiLocalizations.error(widget.language, prefix, error);

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
      _message(_ue('공지 및 안내 조회 실패', e));
    }
  }

  Future<void> _requestDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_u('공지 및 안내 삭제 확인')),
        content: Text(_u(
          '삭제하면 홈 화면에서는 즉시 보이지 않습니다.\n삭제된 자료는 30일 동안 임시 보관 후 완전히 삭제됩니다.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_u('취소'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_u('확인'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ContentService.requestNoticeDeletion(_text(row, 'id'));
      _message(_u('삭제 대기중으로 변경했습니다. 30일 후 완전히 삭제됩니다.'));
      await _load();
    } catch (e) {
      _message(_ue('삭제 요청 실패', e));
    }
  }

  Future<void> _hardDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_u('바로 삭제')),
        content: Text(_u('임시 보관 기간을 무시하고 DB에서 완전히 삭제할까요?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_u('취소'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_u('바로 삭제'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ContentService.hardDeleteNotice(_text(row, 'id'));
      _message(_u('공지 및 안내를 완전히 삭제했습니다.'));
      await _load();
    } catch (e) {
      _message(_ue('바로 삭제 실패', e));
    }
  }

  Future<void> _restore(Map<String, dynamic> row) async {
    try {
      await ContentService.restoreNotice(_text(row, 'id'));
      _message(_u('삭제를 취소했습니다. 홈 화면에 다시 표시됩니다.'));
      await _load();
    } catch (e) {
      _message(_ue('삭제 취소 실패', e));
    }
  }

  Future<void> _showEditor({Map<String, dynamic>? existing}) async {
    final title = TextEditingController(text: _text(existing ?? {}, 'title'));
    final content = TextEditingController(text: _text(existing ?? {}, 'content'));
    final titleEn =
        TextEditingController(text: _text(existing ?? {}, 'title_en'));
    final contentEn =
        TextEditingController(text: _text(existing ?? {}, 'content_en'));
    final titleLo =
        TextEditingController(text: _text(existing ?? {}, 'title_lo'));
    final contentLo =
        TextEditingController(text: _text(existing ?? {}, 'content_lo'));
    bool pinned = existing?['is_pinned'] == true;
    bool showPublishedDate = existing == null || existing['show_published_date'] != false;

    final attachments = contentAttachments(existing?['attachments']);
    bool mediaBusy = false;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(canPop: !mediaBusy && !saving, child: AlertDialog(
          title: Text(_u(existing == null ? '공지 및 안내 추가' : '공지 및 안내 편집')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: _u('제목'),
                    hintText: _u('예: 9월 한국→라오스 해상 일정 안내'),
                  ),
                ),
                TextField(
                  controller: content,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: _u('내용'),
                    hintText: _u('공지 내용을 입력해 주세요.'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _u('비어 있는 영어·라오스어는 자동 번역됩니다. 직접 입력한 번역은 우선 저장됩니다.'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('English · ${_u('직접 입력 (선택)')}'),
                  children: [
                    TextField(
                      controller: titleEn,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    TextField(
                      controller: contentEn,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Content'),
                    ),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('ລາວ · ${_u('직접 입력 (선택)')}'),
                  children: [
                    TextField(
                      controller: titleLo,
                      decoration: const InputDecoration(labelText: 'ຫົວຂໍ້'),
                    ),
                    TextField(
                      controller: contentLo,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'ເນື້ອໃນ'),
                    ),
                  ],
                ),
                IgnorePointer(ignoring: saving, child: ContentMediaEditor(items: attachments, kind: 'notice', language: widget.language, onBusy: (value) { if (dialogContext.mounted) setDialogState(() => mediaBusy=value); })),
                CheckboxListTile(
                  value: showPublishedDate,
                  onChanged: (v) => setDialogState(() => showPublishedDate = v ?? true),
                  title: Text(_u('등록 날짜 표시')),
                ),
                CheckboxListTile(
                  value: pinned,
                  onChanged: (v) => setDialogState(() => pinned = v ?? false),
                  title: Text(_u('상단 고정')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: mediaBusy || saving ? null : () => Navigator.pop(dialogContext),
              child: Text(_u('취소')),
            ),
            FilledButton(
              onPressed: mediaBusy || saving ? null : () async {
                if (title.text.trim().isEmpty || content.text.trim().isEmpty) {
                  _message(_u('제목과 내용을 입력해 주세요.'));
                  return;
                }
                final data = <String, dynamic>{
                  'attachments': attachments,
                  'title': title.text.trim(),
                  'content': content.text.trim(),
                  'title_en': titleEn.text.trim(),
                  'content_en': contentEn.text.trim(),
                  'title_lo': titleLo.text.trim(),
                  'content_lo': contentLo.text.trim(),
                  'is_pinned': pinned,
                  'show_published_date': showPublishedDate,
                  if (existing == null) 'published_at': DateTime.now().toUtc().toIso8601String(),
                };
                setDialogState(() => saving=true);
                try {
                  if (existing == null) {
                    await ContentService.createNotice(data);
                  } else {
                    await ContentService.updateNotice(_text(existing, 'id'), data, expectedUpdatedAt: existing['updated_at']?.toString());
                  }
                  if (dialogContext.mounted) { setDialogState(() => saving=false); Navigator.pop(dialogContext); }
                  await _load();
                } catch (e) {
                  _message(_ue(existing == null ? '작성 실패' : '저장 실패', e));
                } finally {
                  if (dialogContext.mounted) setDialogState(() => saving=false);
                }
              },
              child: Text(_u(existing == null ? '작성' : '저장')),
            ),
          ],
        )),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    content.dispose();
    titleEn.dispose();
    contentEn.dispose();
    titleLo.dispose();
    contentLo.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.role.canEditNotices) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_u('공지 및 안내 관리')),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
        ),
        body: Center(child: Text(_u('관리자 권한이 필요합니다.'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_u('공지 및 안내 목록 관리')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
      ),
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: Text(_u('공지 및 안내 추가')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_items.isEmpty)
                    Card(child: ListTile(title: Text(_u('등록된 공지 및 안내가 없습니다.')))),
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
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8),
                                          child: Chip(label: Text(_u('삭제 대기중'))),
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
                                      child: Text(_u('삭제 취소')),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => _hardDelete(row),
                                      child: Text(_u('바로 삭제')),
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
