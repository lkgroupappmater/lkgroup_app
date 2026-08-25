import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';
import 'notice_list_screen.dart';
import 'notice_management_screen.dart';
import 'schedule_management_screen.dart';
import 'shipment_schedule_screen.dart';

class DashboardHomeBody extends StatefulWidget {
  const DashboardHomeBody(
      {super.key, this.language = AppLanguage.korean, this.currentUser});
  final AppLanguage language;
  final AppUser? currentUser;
  @override
  State<DashboardHomeBody> createState() => _DashboardHomeBodyState();
}

class _DashboardHomeBodyState extends State<DashboardHomeBody> {
  bool _consulting = false;
  bool get _isAdmin => widget.currentUser?.role == UserRole.admin;
  final _question = TextEditingController();
  final _schedules = const [
    {
      'route': '한국-라오스 해상',
      'voyage': '01항차',
      'from': '부산항',
      'to': '비엔티안',
      'date': '2026-08-01',
      'status': '운송 중'
    },
    {
      'route': '한국-라오스 항공',
      'voyage': '02항차',
      'from': '인천공항',
      'to': '와타이공항',
      'date': '2026-07-12',
      'status': '예약 확정'
    }
  ];
  final _notices = const [
    {'title': '2026년 하반기 운송 일정 안내', 'date': '2026-06-20'},
    {'title': '통관 서류 제출 안내', 'date': '2026-06-15'},
    {'title': '공휴일 접수 마감 안내', 'date': '2026-06-10'}
  ];
  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  void _openList(bool schedule) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => _isAdmin
              ? (schedule
                  ? const ScheduleManagementScreen()
                  : const NoticeManagementScreen())
              : (schedule
                  ? const ShipmentScheduleScreen()
                  : const NoticeListScreen())));
  void _consult() {
    if (_question.text.trim().isEmpty) return;
    _question.clear();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상담 요청이 접수되었습니다. 담당자가 확인 후 안내드리겠습니다.')));
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 24), children: [
        _sectionHeader('진행 중인 선적 일정', _isAdmin ? '목록 관리' : '목록 자세히 보기',
            () => _openList(true)),
        ..._schedules.map((s) => Card(
            child: ListTile(
                onTap: () => _openList(true),
                leading:
                    const Icon(Icons.local_shipping, color: AppColors.primary),
                title: Text('${s['route']} · ${s['voyage']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${s['from']} → ${s['to']}\n도착 예정 ${s['date']}'),
                trailing: Text(s['status']!,
                    style: const TextStyle(color: AppColors.tealAccent))))),
        const SizedBox(height: 20),
        _sectionHeader(
            '공지사항', _isAdmin ? '목록 관리' : '목록 자세히 보기', () => _openList(false)),
        ..._notices.map((n) => Card(
            child: ListTile(
                onTap: () => _openList(false),
                leading: const Icon(Icons.campaign_outlined,
                    color: AppColors.primary),
                title: Text(n['title']!),
                subtitle: Text(n['date']!)))),
        const SizedBox(height: 18),
        Card(
            color: AppColors.surface,
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('상담 및 연락처',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary)),
                      const SizedBox(height: 10),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            '카카오톡 단톡방',
                            '오픈상담톡(한국인)',
                            '카카오톡(대표번호)',
                            'WhatsApp(한국인)',
                            'WhatsApp(대표번호)',
                            'Facebook',
                            '네이버'
                          ]
                              .map((e) => ActionChip(
                                  label: Text(e),
                                  onPressed: () => showDialog<void>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                              title: Text(e),
                                              content: const Text(
                                                  '관리자 링크 설정 필요\n실제 링크 등록 후 연결됩니다.'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: const Text('확인'))
                                              ]))))
                              .toList())
                    ]))),
        const SizedBox(height: 16),
        Card(
            child: SwitchListTile(
                value: _consulting,
                onChanged: (v) => setState(() => _consulting = v),
                title: const Text('상담하기'),
                subtitle: const Text('AI 또는 담당자 상담을 시작합니다.'))),
        if (_consulting)
          Card(
              color: AppColors.inputFill,
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AI 상담 준비 중',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                        const SizedBox(height: 8),
                        const Text(
                            '운송 일정·운임 견적·화물 조회·통관 안내 기본 답변을 준비할 수 있습니다.'),
                        const SizedBox(height: 10),
                        TextField(
                            controller: _question,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                hintText: '궁금한 내용을 입력해 주세요.',
                                filled: true,
                                fillColor: Colors.white)),
                        const SizedBox(height: 8),
                        Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                                onPressed: _consult,
                                child: const Text('상담 시작')))
                      ])))
      ]);
  Widget _sectionHeader(String title, String action, VoidCallback onTap) =>
      Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary))),
        TextButton(onPressed: onTap, child: Text(action))
      ]);
}

class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({super.key, this.currentUser});
  final AppUser? currentUser;
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: DashboardHomeBody(currentUser: currentUser)));
}
