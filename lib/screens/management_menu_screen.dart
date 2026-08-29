import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/app_user.dart';
import 'change_approval_screen.dart';
import 'excel_export_screen.dart';
import 'excel_upload_screen.dart';
import 'exchange_rate_screen.dart';
import 'member_management_screen.dart';
import 'notice_management_screen.dart';
import 'quote_request_management_screen.dart';
import 'schedule_management_screen.dart';

class ManagementMenuScreen extends StatelessWidget {
  const ManagementMenuScreen({
    super.key,
    required this.user,
    required this.onOpenCargoManagement,
  });

  final AppUser user;
  final VoidCallback onOpenCargoManagement;

  bool get _isAdmin => user.role == UserRole.admin;
  bool get _isStaff => user.role == UserRole.staff;

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, Object?>>[];

    if (_isAdmin || _isStaff) {
      items.addAll([
        {
          'label': '선적 일정 관리',
          'icon': Icons.calendar_month,
          'page': ScheduleManagementScreen(user: user),
        },
        {
          'label': '공지 및 안내 관리',
          'icon': Icons.campaign_outlined,
          'page': NoticeManagementScreen(user: user),
        },
      ]);
    }

    items.add({
      'label': '화물 종합 관리',
      'icon': Icons.inventory_2_outlined,
      'action': onOpenCargoManagement,
    });

    // 엑셀 업로드/다운로드: 총괄, 직원, 협력/파트너사
    items.addAll([
      {
        'label': '엑셀 화물 업로드',
        'icon': Icons.upload_file_outlined,
        'page': const ExcelUploadScreen(),
      },
      {
        'label': '엑셀 화물 다운로드',
        'icon': Icons.download_outlined,
        'page': const ExcelExportScreen(),
      },
    ]);

    if (_isAdmin) {
      items.addAll([
        {
          'label': '회원 종합 관리',
          'icon': Icons.people_alt_outlined,
          'page': const MemberManagementScreen(),
        },
        {
          'label': '화물 내용 변경 승인 관리',
          'icon': Icons.fact_check_outlined,
          'page': const ChangeApprovalScreen(),
        },
      ]);
    }

    if (_isAdmin || _isStaff) {
      items.addAll([
        {
          'label': '견적 요청 관리',
          'icon': Icons.request_quote_outlined,
          'page': const QuoteRequestManagementScreen(),
        },
        {
          'label': '기준 환율 입력',
          'icon': Icons.currency_exchange,
          'page': const ExchangeRateScreen(),
        },
      ]);
    }

    return Material(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Card(
            color: AppColors.primary,
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                child: user.avatarUrl == null || user.avatarUrl!.trim().isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(
                user.name.isEmpty ? '회원' : user.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                user.roleLabel,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '통합 관리',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.65,
            children: items.map((item) {
              return OutlinedButton.icon(
                onPressed: () {
                  final action = item['action'];
                  if (action is VoidCallback) {
                    action();
                    return;
                  }
                  final page = item['page'];
                  if (page is Widget) {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => page),
                    );
                  }
                },
                icon: Icon(item['icon']! as IconData, size: 18),
                label: Text(
                  item['label']! as String,
                  textAlign: TextAlign.center,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
