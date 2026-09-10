import '../widgets/auto_refresh_state.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/route_catalog.dart';
import '../core/shipment_period_labels.dart';
import '../core/ui_localizations.dart';
import '../models/app_user.dart';
import '../widgets/ai_consultation.dart';
import '../widgets/content_media.dart';
import 'company_content_screen.dart';
import '../services/content_service.dart';
import 'notice_list_screen.dart';
import 'shipment_schedule_screen.dart';
import 'notice_management_screen.dart';
import 'schedule_management_screen.dart';

class ContactLink {
  final String label;
  final String icon;
  final String placeholder;

  const ContactLink({
    required this.label,
    required this.icon,
    required this.placeholder,
  });
}

const _contactLinks = <ContactLink>[
  ContactLink(label: 'LK그룹 카카오톡 단톡방', icon: 'kakao_group', placeholder: 'https://open.kakao.com/o/gvMbtWJc'),
  ContactLink(label: '오픈상담톡(한국어, Eng, ລາວ)', icon: 'kakao_open', placeholder: 'https://open.kakao.com/o/sYly2bxf'),
  ContactLink(label: '카카오톡 대표번호 (Eng, ລາວ)', icon: 'kakao', placeholder: 'http://qr.kakao.com/talk/98dpGrAOWUcmXlhyLxFqtwOS_qQ-'),
  ContactLink(label: 'WhatsApp(한국어, Eng, ລາວ)', icon: 'whatsapp', placeholder: 'https://wa.me/8562052883018'),
  ContactLink(label: 'WhatsApp 대표번호 (Eng, ລາວ)', icon: 'whatsapp', placeholder: 'https://wa.me/8562091126780'),
  ContactLink(label: 'LK Trading Facebook', icon: 'facebook', placeholder: 'https://www.facebook.com/LKTradingofLao'),
  ContactLink(label: 'LK Group 블로그', icon: 'naver', placeholder: 'https://blog.naver.com/lkgrouplaos'),
  ContactLink(label: 'LK Group 사무실 위치', icon: 'google_maps', placeholder: 'https://maps.app.goo.gl/jMEFmjCw1wmJiAqx7'),
];

class _ScheduleItem {
  final String route;
  final String year;
  final String voyage;
  final String departure;
  final String arrival;
  final String status;
  final String detail;
  final List<Map<String,dynamic>> attachments;

  const _ScheduleItem({
    required this.route,
    required this.year,
    required this.voyage,
    required this.departure,
    required this.arrival,
    required this.status,
    required this.detail,
    this.attachments=const [],
  });
}

class _NoticeItem {
  final String title;
  final String date;
  final bool showDate;
  final String content;
  final bool isNew;
  final List<Map<String,dynamic>> attachments;

  const _NoticeItem({
    required this.title,
    required this.date,
    required this.showDate,
    required this.content,
    this.isNew = false,
    this.attachments=const [],
  });
}

class DashboardHomeBody extends StatefulWidget {
  const DashboardHomeBody({
    super.key,
    this.language = AppLanguage.korean,
    this.currentUser,
  });

  final AppLanguage language;
  final AppUser? currentUser;

  @override
  State<DashboardHomeBody> createState() => _DashboardHomeBodyState();
}

class _DashboardHomeBodyState extends State<DashboardHomeBody> with AutoRefreshState<DashboardHomeBody> {
  int _contentRequest = 0;
  @override
  Set<String> get autoRefreshTopics => const {'content'};
  @override
  Future<void> refreshAutomatically() => _loadContent(background: true);

  List<_ScheduleItem> _visibleSchedules = <_ScheduleItem>[];
  List<_NoticeItem> _visibleNotices = <_NoticeItem>[];

  bool get _isManager =>
      widget.currentUser?.role == UserRole.staff ||
      widget.currentUser?.role == UserRole.admin;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void didUpdateWidget(covariant DashboardHomeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      _loadContent();
    }
  }

  String _t(String key) => AppStrings.get(widget.language, key);
  String _u(String korean) => UiLocalizations.get(widget.language, korean);
  String _uf(String korean, Map<String, Object?> values) =>
      UiLocalizations.format(widget.language, korean, values);

  String _contactLabel(ContactLink link) {
    // Translate the service name, but keep the language availability markers
    // exactly as written so users can recognise every supported language.
    if (widget.language == AppLanguage.korean) return link.label;
    const english = <String, String>{
      'LK그룹 카카오톡 단톡방': 'LK Group KakaoTalk Group Chat',
      '오픈상담톡(한국어, Eng, ລາວ)':
          'Open Consultation Chat(한국어, Eng, ລາວ)',
      '카카오톡 대표번호 (Eng, ລາວ)':
          'KakaoTalk Main Number (Eng, ລາວ)',
      'WhatsApp(한국어, Eng, ລາວ)': 'WhatsApp(한국어, Eng, ລາວ)',
      'WhatsApp 대표번호 (Eng, ລາວ)':
          'WhatsApp Main Number (Eng, ລາວ)',
      'LK Trading Facebook': 'LK Trading Facebook',
      'LK Group 블로그': 'LK Group Blog',
      'LK Group 사무실 위치': 'LK Group Office Location',
    };
    const lao = <String, String>{
      'LK그룹 카카오톡 단톡방': 'ກຸ່ມສົນທະນາ KakaoTalk ຂອງ LK Group',
      '오픈상담톡(한국어, Eng, ລາວ)':
          'ຫ້ອງສົນທະນາປຶກສາ(한국어, Eng, ລາວ)',
      '카카오톡 대표번호 (Eng, ລາວ)':
          'ເບີຫຼັກ KakaoTalk (Eng, ລາວ)',
      'WhatsApp(한국어, Eng, ລາວ)': 'WhatsApp(한국어, Eng, ລາວ)',
      'WhatsApp 대표번호 (Eng, ລາວ)':
          'ເບີຫຼັກ WhatsApp (Eng, ລາວ)',
      'LK Trading Facebook': 'Facebook ຂອງ LK Trading',
      'LK Group 블로그': 'ບລັອກ LK Group',
      'LK Group 사무실 위치': 'ທີ່ຕັ້ງສຳນັກງານ LK Group',
    };
    return (widget.language == AppLanguage.lao ? lao : english)[link.label] ??
        link.label;
  }

  String _dateOnly(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '';
    return text.contains('T') ? text.split('T').first : text.split(' ').first;
  }

  Future<void> _loadContent({bool background = false}) async {
    final request = ++_contentRequest;
    final language = widget.language;
    try {
      if (_isManager && !background) {
        await ContentService.backfillMissingTranslations();
      }
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        ContentService.fetchSchedules(language: widget.language),
        ContentService.fetchNotices(language: widget.language),
      ]);
      final schedules = List<Map<String, dynamic>>.from(results[0] as List);
      final notices = List<Map<String, dynamic>>.from(results[1] as List);
      final scheduleItems = schedules
          .map(
            (r) => _ScheduleItem(
              route: RouteCatalog.localizedLabel(
                '${r['route'] ?? ''}',
                widget.language,
              ),
              year: ShipmentPeriodLabels.year(
                r['year'] ?? r['shipment_year'],
                widget.language,
              ),
              voyage: ShipmentPeriodLabels.voyage(
                r['voyage'],
                widget.language,
              ),
              departure: _dateOnly(
                r['booking_close_date'] ??
                    r['closing_date'] ??
                    r['departure_date'],
              ),
              arrival: _dateOnly(
                r['estimated_arrival_date'] ?? r['arrival_date'],
              ),
              status: '${r['status'] ?? '예정'}',
              detail: '${r['detail'] ?? ''}',
              attachments: contentAttachments(r['attachments']),
            ),
          )
          .toList();
      final noticeItems = notices
          .map(
            (r) => _NoticeItem(
              title: '${r['title'] ?? ''}',
              date: _dateOnly(r['published_at'] ?? r['created_at']),
              showDate: r['show_published_date'] != false,
              content: '${r['content'] ?? ''}',
              isNew: r['is_new'] == true,
              attachments: contentAttachments(r['attachments']),
            ),
          )
          .toList();

      if (!mounted || request != _contentRequest || widget.language != language ||
          (background && !canApplyAutoRefresh)) return;

      setState(() {
        _visibleSchedules = scheduleItems;
        _visibleNotices = noticeItems;
      });
    } catch (_) {
      // 실제 DB 데이터만 표시합니다.
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );

    // 일정/공지 추가·삭제대기·삭제취소·편집 후 홈으로 복귀하면
    // 항상 DB를 다시 읽어 현재 상태를 반영합니다.
    if (mounted) {
      await _loadContent();
    }
  }

  void _openSchedule() => _open(
        context,
        _isManager
            ? ScheduleManagementScreen(
                user: widget.currentUser!,
                language: widget.language,
              )
            : ShipmentScheduleScreen(language: widget.language),
      );

  void _openNotice() => _open(
        context,
        _isManager
            ? NoticeManagementScreen(
                user: widget.currentUser!,
                language: widget.language,
              )
            : NoticeListScreen(language: widget.language),
      );

  Future<void> _showScheduleDetail(_ScheduleItem item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('schedule')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(
            '${_t('booking_close')}: ${item.departure}\n'
            '${_t('arrival_expected')}: ${item.arrival}\n'
            '${_uf('상태: {status}', {'status': _u(item.status)})}'
            '${item.detail.trim().isEmpty ? '' : '\n\n${item.detail}'}',
          ), ContentMediaGallery(items: item.attachments, language: widget.language)]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showNoticeDetail(_NoticeItem item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(
            '${item.showDate ? item.date : ''}'
            '${item.content.trim().isEmpty ? '' : '${item.showDate ? '\n\n' : ''}${item.content}'}',
          ), ContentMediaGallery(items: item.attachments, language: widget.language)]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showContact(ContactLink link) async {
    if (link.placeholder == '차후 공유') {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_contactLabel(link)),
          content: Text(_u('대표번호 링크는 추후 관리자 설정이 필요합니다.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('close')),
            ),
          ],
        ),
      );
      return;
    }

    if (link.label == 'LK그룹 카카오톡 단톡방') {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          Future<void>.delayed(const Duration(seconds: 3), () async {
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            await launchUrl(
              Uri.parse(link.placeholder),
              mode: LaunchMode.externalApplication,
            );
          });
          return AlertDialog(
            content: Text(
              _u('참여 코드 9112'),
              textAlign: TextAlign.center,
            ),
          );
        },
      );
      return;
    }

    final uri = Uri.tryParse(link.placeholder);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message(_u('링크를 열 수 없습니다.'));
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 118),
          children: [
            _sectionHeader(
              _t('schedule'),
              _isManager ? _t('list_manage') : _t('list_details'),
              _openSchedule,
            ),
            const SizedBox(height: 8),
            ..._visibleSchedules.map(_scheduleCard),
            const SizedBox(height: 14),
            _sectionHeader(
              _t('notice'),
              _isManager ? _t('list_manage') : _t('list_details'),
              _openNotice,
            ),
            const SizedBox(height: 8),
            ..._visibleNotices.map(_noticeCard),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _open(context, CompanyContentScreen(language: widget.language)),
              icon: const Icon(Icons.business_outlined),
              label: Text(sharedText(widget.language,'회사 소개·활동·자료실','Company / activities / resources','ບໍລິສັດ / ກິດຈະກຳ / ຂໍ້ມູນ')),
            ),
            const SizedBox(height: 14),
            _contactSection(),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: AiConsultationBubble(language: widget.language),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    String title,
    String action,
    VoidCallback onPressed,
  ) =>
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: onPressed,
            child: Text(
              action,
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );

  Widget _scheduleCard(_ScheduleItem item) {
    final inTransit = item.status == '운송 중' ||
        item.status == 'In Transit' ||
        item.status == 'ກຳລັງຂົນສົ່ງ';
    final color = inTransit ? AppColors.accent : AppColors.primary;

    return InkWell(
      onTap: () => _showScheduleDetail(item),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: .15),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.route} · ${item.year} · ${item.voyage}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_t('booking_close')}: ${item.departure}  '
                    '${_t('arrival_expected')}: ${item.arrival}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _u(item.status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noticeCard(_NoticeItem item) => InkWell(
        onTap: () => _showNoticeDetail(item),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: .15),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: .06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (item.isNew)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade600,
                    ),
                  ),
                ),
              if (item.showDate)
                Text(
                  item.date,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _contactSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('contact'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(
            (_contactLinks.length / 2).ceil(),
            (row) {
              final left = _contactLinks[row * 2];
              final rightIndex = row * 2 + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(child: _contactCard(left)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: rightIndex < _contactLinks.length
                          ? _contactCard(_contactLinks[rightIndex])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );

  Widget _contactLogo(String type) {
    switch (type) {
      case 'kakao_group':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE812),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.groups_rounded, size: 16, color: Color(0xFF1E1E1E)),
        );
      case 'kakao_open':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE812),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.forum_rounded, size: 15, color: Color(0xFF1E1E1E)),
        );
      case 'kakao':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE812),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.chat_bubble_rounded, size: 15, color: Color(0xFF1E1E1E)),
        );
      case 'whatsapp':
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFF25D366),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.phone_rounded, size: 15, color: Colors.white),
        );
      case 'facebook':
        return Image.asset(
          'assets/images/facebook_icon.png',
          width: 24,
          height: 24,
          fit: BoxFit.contain,
        );
      case 'naver':
        return Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF03C75A),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text(
            'N',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      case 'google_maps':
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/images/google_maps_icon.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        );
      default:
        return const SizedBox(width: 24, height: 24);
    }
  }

  Widget _contactCard(ContactLink link) => InkWell(
        onTap: () => _showContact(link),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: .18),
            ),
          ),
          child: Row(
            children: [
              _contactLogo(link.icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _contactLabel(link),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

}

class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({
    super.key,
    this.currentUser,
  });

  final AppUser? currentUser;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: DashboardHomeBody(currentUser: currentUser),
        ),
      );
}
