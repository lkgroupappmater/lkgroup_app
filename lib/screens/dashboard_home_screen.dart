import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';
import '../services/content_service.dart';
import 'notice_list_screen.dart';
import 'shipment_schedule_screen.dart';

class ContactLink {
  final String label;
  final String icon;
  final String placeholder;
  const ContactLink({required this.label, required this.icon, required this.placeholder});
}

const _contactLinks = <ContactLink>[
  ContactLink(label: '카카오톡 단톡방', icon: '💬', placeholder: 'https://open.kakao.com/o/gvMbtWJc'),
  ContactLink(label: '오픈상담톡(한국어, Eng, ລາວ)', icon: '💛', placeholder: 'https://open.kakao.com/o/sYly2bxf'),
  ContactLink(label: '카카오톡(대표번호)', icon: '📱', placeholder: 'http://qr.kakao.com/talk/98dpGrAOWUcmXlhyLxFqtwOS_qQ-'),
  ContactLink(label: 'WhatsApp(한국어, Eng, ລາວ)', icon: '🟢', placeholder: 'https://wa.me/8562052883018'),
  ContactLink(label: 'WhatsApp(대표번호)', icon: '📲', placeholder: 'https://wa.me/8562091126780'),
  ContactLink(label: 'Facebook', icon: '🔵', placeholder: 'https://www.facebook.com/LKTradingofLao'),
  ContactLink(label: '네이버', icon: '🟩', placeholder: 'https://blog.naver.com/lkgrouplaos'),
];

class _ScheduleItem {
  final String route, departure, arrival, status;
  const _ScheduleItem({required this.route, required this.departure, required this.arrival, required this.status});
}

const _schedules = <_ScheduleItem>[
  _ScheduleItem(route: '인천 → 상하이', departure: '2025-07-10', arrival: '2025-07-12', status: '운송 중'),
  _ScheduleItem(route: '부산 → 도쿄', departure: '2025-07-14', arrival: '2025-07-16', status: '예정'),
  _ScheduleItem(route: '인천 → LA', departure: '2025-07-18', arrival: '2025-08-01', status: '예정'),
];

class _NoticeItem {
  final String title, date;
  final bool isNew;
  const _NoticeItem({required this.title, required this.date, this.isNew = false});
}

const _notices = <_NoticeItem>[
  _NoticeItem(title: '2025년 하반기 운임 조정 안내', date: '2025-07-01', isNew: true),
  _NoticeItem(title: '중국 항구 임시 파업 관련 공지', date: '2025-06-28', isNew: true),
  _NoticeItem(title: '통관 서류 제출 기한 변경 안내', date: '2025-06-20'),
];

class DashboardHomeBody extends StatefulWidget {
  const DashboardHomeBody({super.key, this.language = AppLanguage.korean, this.currentUser});
  final AppLanguage language;
  final AppUser? currentUser;
  @override
  State<DashboardHomeBody> createState() => _DashboardHomeBodyState();
}

class _DashboardHomeBodyState extends State<DashboardHomeBody> {
  bool _consultationOpen = false;
  List<_ScheduleItem> _visibleSchedules = _schedules;
  List<_NoticeItem> _visibleNotices = _notices;
  final _questionController = TextEditingController();

  bool get _isManager => widget.currentUser?.role == UserRole.staff || widget.currentUser?.role == UserRole.admin;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final schedules = await ContentService.fetchSchedules();
      final notices = await ContentService.fetchNotices();
      if (!mounted) return;
      setState(() {
        if (schedules.isNotEmpty) {
          _visibleSchedules = schedules.map((r) => _ScheduleItem(route: '${r['origin'] ?? ''} → ${r['destination'] ?? ''}', departure: (r['closing_date'] ?? '').toString(), arrival: (r['arrival_date'] ?? '').toString(), status: '예정')).toList();
        }
        if (notices.isNotEmpty) {
          _visibleNotices = notices.map((r) => _NoticeItem(title: (r['title'] ?? '').toString(), date: (r['published_at'] ?? '').toString().split('T').first, isNew: false)).toList();
        }
      });
    } catch (_) {
      // Empty/unconfigured Supabase keeps the existing standard mock layout.
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  void _open(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  // 일정/공지의 상세 목록은 모든 사용자에게 공개합니다.
  // 관리자용 추가·편집·삭제는 화물 관리 > 통합 관리에서만 접근합니다.
  void _openSchedule() => _open(context, const ShipmentScheduleScreen());
  void _openNotice() => _open(context, const NoticeListScreen());

  Future<void> _showContact(ContactLink link) async {
    if (link.placeholder == '차후 공유') {
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: Text(link.label), content: const Text('대표번호 링크는 추후 관리자 설정이 필요합니다.'), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('닫기'))]));
      return;
    }
    if (link.label == '카카오톡 단톡방') {
      await showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) {
        Future<void>.delayed(const Duration(seconds: 3), () async {
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          await launchUrl(Uri.parse(link.placeholder), mode: LaunchMode.externalApplication);
        });
        return const AlertDialog(content: Text('참여 코드 9112', textAlign: TextAlign.center));
      });
      return;
    }
    final uri = Uri.tryParse(link.placeholder);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) _message('링크를 열 수 없습니다.');
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _startConsultation() {
    if (_questionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('질문을 입력해 주세요.')));
      return;
    }
    // TODO: 상담 내용을 Supabase/AI 상담 API에 전송하고 답변을 저장합니다.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('상담 요청이 접수되었습니다. 담당자가 확인 후 안내드리겠습니다.')));
    _questionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 118),
        children: [
          _sectionHeader('선적 일정', '목록 자세히 보기', _openSchedule),
          const SizedBox(height: 8),
          ..._visibleSchedules.map(_scheduleCard),
          const SizedBox(height: 14),
          _sectionHeader('공지사항', '목록 자세히 보기', _openNotice),
          const SizedBox(height: 8),
          ..._visibleNotices.map(_noticeCard),
          const SizedBox(height: 14),
          _contactSection(),
        ],
      ),
      Positioned(left: 0, right: 0, bottom: 0, child: _consultationArea()),
    ]);
  }

  Widget _sectionHeader(String title, String action, VoidCallback onPressed) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary))),
    TextButton(onPressed: onPressed, child: Text(action, style: const TextStyle(color: AppColors.accent, fontSize: 13))),
  ]);

  Widget _scheduleCard(_ScheduleItem item) {
    final color = item.status == '운송 중' ? AppColors.accent : AppColors.primary;
    return InkWell(
      onTap: _openSchedule,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primary.withValues(alpha: .15)), boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: .06), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.route, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
            const SizedBox(height: 4),
            Text('출발: ${item.departure}  도착: ${item.arrival}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text(item.status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
        ]),
      ),
    );
  }

  Widget _noticeCard(_NoticeItem item) => InkWell(
    onTap: _openNotice,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primary.withValues(alpha: .15)), boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: .06), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Row(children: [
        Expanded(child: Text(item.title, style: const TextStyle(fontSize: 14, color: AppColors.primary))),
        if (item.isNew) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)), child: Text('NEW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade600))),
        Text(item.date, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ]),
    ),
  );

  Widget _contactSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('상담 및 연락처', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
    const SizedBox(height: 12),
    ...List.generate((_contactLinks.length / 2).ceil(), (row) {
      final left = _contactLinks[row * 2];
      final rightIndex = row * 2 + 1;
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [Expanded(child: _contactCard(left)), const SizedBox(width: 10), Expanded(child: rightIndex < _contactLinks.length ? _contactCard(_contactLinks[rightIndex]) : const SizedBox.shrink())]));
    }),
  ]);

  Widget _contactCard(ContactLink link) => InkWell(onTap: () => _showContact(link), borderRadius: BorderRadius.circular(10), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .05), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primary.withValues(alpha: .18))), child: Row(children: [Text(link.icon, style: const TextStyle(fontSize: 20)), const SizedBox(width: 8), Expanded(child: Text(link.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)))])));

  Widget _consultationArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_consultationOpen) _consultationPanel(),
        InkWell(
          onTap: () => setState(() => _consultationOpen = !_consultationOpen),
          child: Container(
            width: double.infinity,
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _consultationOpen
                      ? Icons.keyboard_arrow_down
                      : Icons.chat_bubble_outline,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  _consultationOpen ? '상담 닫기' : '상담하기',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _consultationPanel() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI 상담 준비 중',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '운송 일정·운임·화물 조회·통관 안내 기본 답변을 준비하고 있습니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  decoration: const InputDecoration(
                    hintText: '질문을 입력하세요...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _startConsultation,
                child: const Text('상담 시작'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({super.key, this.currentUser});
  final AppUser? currentUser;
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, body: SafeArea(child: DashboardHomeBody(currentUser: currentUser)));
}





