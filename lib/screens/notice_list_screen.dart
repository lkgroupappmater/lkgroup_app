import '../widgets/auto_refresh_state.dart';
import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../services/content_service.dart';
import '../widgets/content_media.dart';

class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({
    super.key,
    this.language = AppLanguage.korean,
  });

  final AppLanguage language;

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> with AutoRefreshState<NoticeListScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  Set<String> get autoRefreshTopics => const {'content'};
  @override
  Future<void> refreshAutomatically() async {
    final before = _future;
    final rows = await _load();
    if (!canApplyAutoRefresh || before != _future) return;
    setState(() => _future = Future.value(rows));
  }


  String _t(String key) => AppStrings.get(widget.language, key);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    return ContentService.fetchNotices(language: widget.language);
  }

  String _v(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('notice_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
      ),
      backgroundColor: AppColors.background,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('${_t('notice_load_failed')}\n${snapshot.error}'),
            );
          }
          final rows = snapshot.data ?? <Map<String, dynamic>>[];
          if (rows.isEmpty) return Center(child: Text(_t('no_notice')));
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final notice = rows[index];
                return Container(
                  key: ValueKey(notice['id']),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: ExpansionTile(
                    title: Text(
                      _v(notice, 'title'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: notice['show_published_date'] == false
                        ? null
                        : Text(
                            _v(notice, 'published_at').split('T').first,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    children: <Widget>[
                      ContentMediaGallery(items: contentAttachments(notice['attachments']), language: widget.language),
                      const Divider(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _v(notice, 'content'),
                          style: const TextStyle(
                            height: 1.6,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
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
