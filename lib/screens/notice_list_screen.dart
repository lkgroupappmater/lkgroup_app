// lib/screens/notice_list_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class NoticeListScreen extends StatelessWidget {
  const NoticeListScreen({super.key});

  static const List<Map<String, String>> _notices = [
    {
      'title': '7월 정기 스케줄 변경 안내',
      'date': '2025-07-01',
      'content': '7월 15일 한국-라오스 해상 편 일정이 변경되었습니다.\n'
          '기존 출항일: 7월 15일 → 변경: 7월 17일\n'
          '자세한 내용은 고객센터로 문의해 주세요.',
    },
    {
      'title': '추석 연휴 휴무 안내',
      'date': '2025-06-25',
      'content': '추석 연휴(9월 26일~10월 2일) 기간 동안 접수 및 상담이 제한됩니다.\n'
          '긴급 문의는 WhatsApp으로 연락 부탁드립니다.',
    },
    {
      'title': '라오스 통관 강화 안내',
      'date': '2025-06-10',
      'content': '라오스 세관에서 7월부터 전자제품 반입 관련 서류 제출을 강화합니다.\n'
          '영수증, 사용 목적 확인서 등 추가 서류 준비가 필요합니다.',
    },
    {
      'title': '신규 노선 개통: 라오스-캄보디아 육로',
      'date': '2025-05-20',
      'content': '라오스-캄보디아 육로 노선이 새로 개통되었습니다.\n'
          '비엔티안 → 프놈펜 구간 운송 서비스를 시작합니다.',
    },
    {
      'title': '여름 성수기 배송 지연 안내',
      'date': '2025-05-10',
      'content': '7~8월 여름 성수기 기간 중 배송이 2~5일 지연될 수 있습니다.\n'
          '중요한 화물은 항공편 이용을 권장드립니다.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyPrimary,
        foregroundColor: AppColors.white,
        title: const Text('공지사항',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: _notices.length,
        itemBuilder: (context, i) {
          final n = _notices[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ExpansionTile(
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              leading: Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              title: Text(n['title']!,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              subtitle: Text(n['date']!,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textHint)),
              children: [
                const Divider(height: 1, color: AppColors.divider),
                const SizedBox(height: 10),
                Text(n['content']!,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: AppColors.textSecondary)),
              ],
            ),
          );
        },
      ),
    );
  }
}
