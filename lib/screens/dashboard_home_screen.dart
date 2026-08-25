import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';
import 'notice_list_screen.dart';
import 'notice_management_screen.dart';
import 'schedule_management_screen.dart';
import 'shipment_schedule_screen.dart';

class DashboardHomeBody extends StatelessWidget {
  const DashboardHomeBody(
      {super.key, this.language = AppLanguage.korean, this.currentUser});
  final AppLanguage language;
  final AppUser? currentUser;

  bool get _isManager => currentUser?.role == UserRole.staff || currentUser?.role == UserRole.admin;

  void _openList(BuildContext context, bool schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isManager
            ? (schedule
                ? const ScheduleManagementScreen()
                : const NoticeManagementScreen())
            : (schedule
                ? const ShipmentScheduleScreen()
                : const NoticeListScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const schedules = [
      {'route': '한국-라오스 해상', 'voyage': '01항차', 'from': '부산항', 'to': '비엔티안', 'date': '2026-08-01', 'status': '운송 중'},
      {'route': '한국-라오스 항공', 'voyage': '02항차', 'from': '인천공항', 'to': '와타이공항', 'date': '2026-07-12', 'status': '예약 확정'},
    ];
    const notices = [
      {'title': '2026년 하반기 운송 일정 안내', 'date': '2026-06-20'},
      {'title': '통관 서류 제출 안내', 'date': '2026-06-15'},
      {'title': '공휴일 접수 마감 안내', 'date': '2026-06-10'},
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        _sectionHeader(context, '선적 일정', _isManager ? '목록 관리' : '목록 자세히 보기', true),
        ...schedules.map((item) => Card(
              child: ListTile(
                onTap: () => _openList(context, true),
                leading: const Icon(Icons.local_shipping, color: AppColors.primary),
                title: Text('${item['route']} · ${item['voyage']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${item['from']} → ${item['to']}\n도착 예정 ${item['date']}'),
                trailing: Text(item['status']!, style: const TextStyle(color: AppColors.tealAccent)),
              ),
            )),
        const SizedBox(height: 20),
        _sectionHeader(context, '공지사항', _isManager ? '목록 관리' : '목록 자세히 보기', false),
        ...notices.map((item) => Card(
              child: ListTile(
                onTap: () => _openList(context, false),
                leading: const Icon(Icons.campaign_outlined, color: AppColors.primary),
                title: Text(item['title']!),
                subtitle: Text(item['date']!),
              ),
            )),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String action, bool schedule) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.primary))),
        TextButton(onPressed: () => _openList(context, schedule), child: Text(action)),
      ],
    );
  }
}

class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({super.key, this.currentUser});
  final AppUser? currentUser;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: DashboardHomeBody(currentUser: currentUser)),
      );
}

