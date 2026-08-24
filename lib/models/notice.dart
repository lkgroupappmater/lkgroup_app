// lib/models/notice.dart

enum NoticeCategory { urgent, system, regulation, general, event }

class Notice {
  final String id;
  final String title;
  final String summary;
  final String content;
  final String date;
  final NoticeCategory category;
  final bool isPinned;

  const Notice({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.date,
    required this.category,
    this.isPinned = false,
  });

  String get categoryLabel {
    switch (category) {
      case NoticeCategory.urgent:
        return '긴급';
      case NoticeCategory.system:
        return '시스템';
      case NoticeCategory.regulation:
        return '규정';
      case NoticeCategory.general:
        return '일반';
      case NoticeCategory.event:
        return '이벤트';
    }
  }
}
