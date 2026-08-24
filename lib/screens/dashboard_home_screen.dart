import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import 'shipment_schedule_screen.dart';
import 'notice_list_screen.dart';

// ---------------------------------------------------------------------------
// ContactLink model (defined here to keep the file self-contained)
// ---------------------------------------------------------------------------
class ContactLink {
  final String label;
  final String icon; // emoji used as a simple icon
  final String placeholder; // TODO: replace with real URL when available

  const ContactLink({
    required this.label,
    required this.icon,
    required this.placeholder,
  });
}

// ---------------------------------------------------------------------------
// Contact list – ORDER MUST NOT CHANGE
// ---------------------------------------------------------------------------
const List<ContactLink> _contactLinks = [
  ContactLink(
    label: '카카오톡 단톡방',
    icon: '💬',
    placeholder: 'https://example.com/kakao-group',
  ),
  ContactLink(
    label: '오픈상담톡(한국인)',
    icon: '💛',
    placeholder: 'https://example.com/kakao-open-kr',
  ),
  ContactLink(
    label: '카카오톡(대표번호)',
    icon: '📱',
    placeholder: 'https://example.com/kakao-main',
  ),
  ContactLink(
    label: 'WhatsApp(한국인)',
    icon: '🟢',
    placeholder: 'https://example.com/whatsapp-kr',
  ),
  ContactLink(
    label: 'WhatsApp(대표번호)',
    icon: '📲',
    placeholder: 'https://example.com/whatsapp-main',
  ),
  ContactLink(
    label: 'Facebook',
    icon: '🔵',
    placeholder: 'https://example.com/facebook',
  ),
  ContactLink(
    label: '네이버',
    icon: '🟩',
    placeholder: 'https://example.com/naver',
  ),
];

// ---------------------------------------------------------------------------
// Internal mock data models
// ---------------------------------------------------------------------------
class _ScheduleItem {
  final String route;
  final String departure;
  final String arrival;
  final String status;

  const _ScheduleItem({
    required this.route,
    required this.departure,
    required this.arrival,
    required this.status,
  });
}

class _NoticeItem {
  final String title;
  final String date;
  final bool isNew;

  const _NoticeItem({
    required this.title,
    required this.date,
    this.isNew = false,
  });
}

const List<_ScheduleItem> _schedules = [
  _ScheduleItem(
    route: '인천 → 상하이',
    departure: '2025-07-10',
    arrival: '2025-07-12',
    status: '운송 중',
  ),
  _ScheduleItem(
    route: '부산 → 도쿄',
    departure: '2025-07-14',
    arrival: '2025-07-16',
    status: '예정',
  ),
  _ScheduleItem(
    route: '인천 → LA',
    departure: '2025-07-18',
    arrival: '2025-08-01',
    status: '예정',
  ),
];

const List<_NoticeItem> _notices = [
  _NoticeItem(
    title: '2025년 하반기 운임 조정 안내',
    date: '2025-07-01',
    isNew: true,
  ),
  _NoticeItem(
    title: '중국 항구 임시 파업 관련 공지',
    date: '2025-06-28',
    isNew: true,
  ),
  _NoticeItem(
    title: '통관 서류 제출 기한 변경 안내',
    date: '2025-06-20',
  ),
];

// ---------------------------------------------------------------------------
// DashboardHomeScreen – wrapper for backward-compatibility
// ---------------------------------------------------------------------------
class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: DashboardHomeBody(),
    );
  }
}

// ---------------------------------------------------------------------------
// DashboardHomeBody – body-only widget used by AppShell
// ---------------------------------------------------------------------------
class DashboardHomeBody extends StatefulWidget {
  const DashboardHomeBody({
    super.key,
    this.language = AppLanguage.korean,
  });

  final AppLanguage language;

  @override
  State<DashboardHomeBody> createState() => _DashboardHomeBodyState();
}

class _DashboardHomeBodyState extends State<DashboardHomeBody> {
  bool _consultationOpen = false;
  final TextEditingController _questionController = TextEditingController();

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  void _showContactDialog(BuildContext context, ContactLink link) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          link.label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryNavy,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '관리자 링크 설정 필요',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              link.placeholder,
              style: TextStyle(
                color: Colors.blue.shade700,
                decoration: TextDecoration.underline,
              ),
            ),
            const SizedBox(height: 12),
            // TODO: replace the dialog action below with url_launcher or
            //       Navigator-based WebView when real URLs are configured.
            const Text(
              '실제 링크가 등록되면 이 버튼으로 이동합니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  void _startConsultation() {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('질문을 입력해 주세요.')),
      );
      return;
    }
    // TODO: connect to real AI consultation service
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('상담 요청: "$question" (현재 mock 응답)')),
    );
    _questionController.clear();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main scrollable content
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _buildScheduleSection(context),
            const SizedBox(height: 24),
            _buildNoticeSection(context),
            const SizedBox(height: 24),
            _buildContactSection(context),
            const SizedBox(height: 16),
          ],
        ),

        // Consultation toggle + panel pinned to bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildConsultationArea(context),
        ),
      ],
    );
  }

  // ── Section: 선적 일정 ──────────────────────────────────────────────────

  Widget _buildScheduleSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '선적 일정',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryNavy,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ShipmentScheduleScreen(),
                  ),
                );
              },
              child: const Text(
                '목록 자세히 보기',
                style: TextStyle(
                  color: AppColors.accentTeal,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._schedules.map((item) => _buildScheduleCard(item)),
      ],
    );
  }

  Widget _buildScheduleCard(_ScheduleItem item) {
    final Color statusColor = item.status == '운송 중'
        ? AppColors.accentTeal
        : AppColors.primaryNavy;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primaryNavy.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.06),
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
                  item.route,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.primaryNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '출발: ${item.departure}  도착: ${item.arrival}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              item.status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section: 공지사항 ────────────────────────────────────────────────────

  Widget _buildNoticeSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '공지사항',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryNavy,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NoticeListScreen(),
                  ),
                );
              },
              child: const Text(
                '목록 자세히 보기',
                style: TextStyle(
                  color: AppColors.accentTeal,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._notices.map((item) => _buildNoticeCard(item)),
      ],
    );
  }

  Widget _buildNoticeCard(_NoticeItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primaryNavy.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.06),
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
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.primaryNavy,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (item.isNew)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade200),
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
          Text(
            item.date,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ── Section: 상담 및 연락처 ──────────────────────────────────────────────

  Widget _buildContactSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '상담 및 연락처',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryNavy,
          ),
        ),
        const SizedBox(height: 12),
        // 2-column grid that preserves list order (left-to-right, top-to-bottom)
        _buildContactGrid(context),
      ],
    );
  }

  Widget _buildContactGrid(BuildContext context) {
    // Build rows of 2, preserving _contactLinks order strictly.
    final List<Widget> rows = [];
    for (int i = 0; i < _contactLinks.length; i += 2) {
      final ContactLink left = _contactLinks[i];
      final bool hasRight = i + 1 < _contactLinks.length;
      final ContactLink? right = hasRight ? _contactLinks[i + 1] : null;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(child: _buildContactCard(context, left)),
              const SizedBox(width: 10),
              Expanded(
                child: right != null
                    ? _buildContactCard(context, right)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _buildContactCard(BuildContext context, ContactLink link) {
    return GestureDetector(
      onTap: () => _showContactDialog(context, link),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primaryNavy.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.primaryNavy.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Text(link.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                link.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Consultation toggle + panel ──────────────────────────────────────────

  Widget _buildConsultationArea(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_consultationOpen) _buildConsultationPanel(context),
        _buildConsultationToggle(context),
      ],
    );
  }

  Widget _buildConsultationToggle(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _consultationOpen = !_consultationOpen),
      child: Container(
        width: double.infinity,
        color: AppColors.primaryNavy,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _consultationOpen ? Icons.keyboard_arrow_down : Icons.chat_bubble_outline,
              color: Colors.white,
              size: 20,
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
    );
  }

  Widget _buildConsultationPanel(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI status badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'AI 상담 준비 중',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quick answer examples
            const Text(
              '자주 묻는 질문',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _QuickChip(label: '운송 일정'),
                _QuickChip(label: '운임 견적'),
                _QuickChip(label: '화물 조회'),
                _QuickChip(label: '통관 안내'),
              ],
            ),
            const SizedBox(height: 14),

            // Question input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      hintText: '질문을 입력하세요...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppColors.primaryNavy.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppColors.primaryNavy.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.accentTeal,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _startConsultation(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _startConsultation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '상담 시작',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helper widget for quick-answer chips
// ---------------------------------------------------------------------------
class _QuickChip extends StatelessWidget {
  final String label;

  const _QuickChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentTeal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.accentTeal.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.accentTeal,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}


