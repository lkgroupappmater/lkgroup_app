import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';
import '../services/admin_management_status_service.dart';
import 'change_approval_screen.dart';
import 'additional_feature_development_screen.dart';
import 'excel_export_screen.dart';
import 'excel_bulk_management_screen.dart';
import 'exchange_rate_screen.dart';
import 'member_management_screen.dart';
import 'notice_management_screen.dart';
import 'quote_request_management_screen.dart';
import 'schedule_management_screen.dart';
import 'discount_management_screen.dart';
import 'local_delivery_management_screen.dart';
import 'unloading_list_management_screen.dart';
import 'voyage_total_management_screen.dart';

import './customer_list_management_screen.dart';
class ManagementMenuScreen extends StatefulWidget {
  const ManagementMenuScreen({
    super.key,
    required this.user,
    required this.onOpenCargoManagement,
    this.language = AppLanguage.korean,
  });

  final AppUser user;
  final VoidCallback onOpenCargoManagement;
  final AppLanguage language;

  @override
  State<ManagementMenuScreen> createState() => _ManagementMenuScreenState();
}

class _ManagementMenuScreenState extends State<ManagementMenuScreen> {
  Map<String, ManagementMenuStatus> _status = const {};

  bool get _isAdmin => widget.user.role == UserRole.admin;
  bool get _isStaff => widget.user.role == UserRole.staff;

  String _m(String korean) {
    if (widget.language == AppLanguage.korean) return korean;
    const english = <String, String>{
      '선적 일정 관리': 'Shipping Schedule',
      '공지 및 안내 관리': 'Notices',
      '하역 자료 관리': 'Unloading Data',
      '고객 리스트': 'Customer List',
      '화물 종합 관리': 'Cargo Management',
      '화물 데이타 엑셀 파일 관리': 'Cargo Excel Files',
      '추가 기능 개발': 'Additional Features',
      '회원 종합 관리': 'Member Management',
      '화물 내용 변경 승인 관리': 'Change Approvals',
      '엑셀 데이타 일괄 관리\n(편집 잠금/해제, 구획 및 영수 번호 관리)': 'Bulk Excel Management\n(Edit lock, zone & receipt)',
      '할인 적용 관리': 'Discounts',
      '시내.지방 배송 관리': 'Local Delivery',
      '항차별 총액 관리': 'Voyage Totals',
      '견적 요청 관리': 'Quote Requests',
      '기준 환율 입력': 'Exchange Rates',
      '회원': 'Member',
      '통합 관리': 'Management',
    };
    const lao = <String, String>{
      '선적 일정 관리': 'ຕາຕະລາງຂົນສົ່ງ',
      '공지 및 안내 관리': 'ແຈ້ງການ',
      '하역 자료 관리': 'ຂໍ້ມູນລົງສິນຄ້າ',
      '고객 리스트': 'ລາຍຊື່ລູກຄ້າ',
      '화물 종합 관리': 'ຈັດການສິນຄ້າ',
      '화물 데이타 엑셀 파일 관리': 'ໄຟລ໌ Excel ສິນຄ້າ',
      '추가 기능 개발': 'ຟັງຊັນເພີ່ມເຕີມ',
      '회원 종합 관리': 'ຈັດການສະມາຊິກ',
      '화물 내용 변경 승인 관리': 'ອະນຸມັດການປ່ຽນແປງ',
      '엑셀 데이타 일괄 관리\n(편집 잠금/해제, 구획 및 영수 번호 관리)': 'ຈັດການ Excel ຈຳນວນຫຼາຍ',
      '할인 적용 관리': 'ຈັດການສ່ວນລົດ',
      '시내.지방 배송 관리': 'ຈັດການຈັດສົ່ງພາຍໃນ',
      '항차별 총액 관리': 'ຍອດລວມແຕ່ລະຖ້ຽວ',
      '견적 요청 관리': 'ຄຳຂໍໃບສະເໜີລາຄາ',
      '기준 환율 입력': 'ອັດຕາແລກປ່ຽນ',
      '회원': 'ສະມາຊິກ',
      '통합 관리': 'ການຈັດການ',
    };
    return (widget.language == AppLanguage.lao ? lao : english)[korean] ??
        korean;
  }

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (!_isAdmin) return;
    final value = await AdminManagementStatusService.instance.fetch();
    if (mounted) setState(() => _status = value);
  }

  Future<void> _openMenu(
    BuildContext context,
    Map<String, Object?> item,
  ) async {
    final menuKey = '${item['menuKey'] ?? ''}';
    if (_isAdmin && menuKey.isNotEmpty) {
      await AdminManagementStatusService.instance.markSeen(menuKey);
    }

    final action = item['action'];
    if (action is VoidCallback) {
      action();
      if (mounted) await _loadStatus();
      return;
    }

    final page = item['page'];
    if (page is Widget) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
      if (mounted) await _loadStatus();
    }
  }

  Widget _menuLabel(Map<String, Object?> item) {
    final label = item['label']! as String;
    final compactLabel = item['compactLabel'] == true;
    final menuKey = '${item['menuKey'] ?? ''}';
    final status = _status[menuKey];
    final count = status?.pendingCount ?? 0;
    final activity = status?.activityType;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: compactLabel ? 4 : null,
          overflow: compactLabel ? TextOverflow.ellipsis : null,
          style: compactLabel
              ? const TextStyle(fontSize: 12, height: 1.12)
              : null,
        ),
        if (count > 0 || activity != null) ...[
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 2,
            children: [
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (activity == 'new')
                const Text(
                  'New',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              if (activity == 'update')
                const Text(
                  'Update',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final items = <Map<String, Object?>>[];

    if (_isAdmin || _isStaff) {
      items.addAll([
        {
          'label': _m('선적 일정 관리'),
          'icon': Icons.calendar_month,
          'page': ScheduleManagementScreen(user: user),
        },
        {
          'label': _m('공지 및 안내 관리'),
          'icon': Icons.campaign_outlined,
          'page': NoticeManagementScreen(user: user),
        },
        {
          'label': _m('하역 자료 관리'),
          'icon': Icons.view_column_outlined,
          'page': const UnloadingListManagementScreen(),
        },
      ]);
      items.addAll([
        {
          'label': _m('고객 리스트'),
          'icon': Icons.view_column_outlined,
          'page': const CustomerListManagementScreen(),
        },
      ]);
    }

    items.add({
      'label': _m('화물 종합 관리'),
      'icon': Icons.inventory_2_outlined,
      'menuKey': 'cargo_management',
      'action': widget.onOpenCargoManagement,
    });

    items.add({
      'label': _m('화물 데이타 엑셀 파일 관리'),
      'icon': Icons.folder_copy_outlined,
      'page': const ExcelExportScreen(),
    });

    if (_isAdmin) {
      items.addAll([
        {
          'label': _m('추가 기능 개발'),
          'icon': Icons.developer_mode_outlined,
          'page': const AdditionalFeatureDevelopmentScreen(),
        },
        {
          'label': _m('회원 종합 관리'),
          'icon': Icons.people_alt_outlined,
          'menuKey': 'member_management',
          'page': const MemberManagementScreen(),
        },
        {
          'label': _m('화물 내용 변경 승인 관리'),
          'icon': Icons.fact_check_outlined,
          'menuKey': 'change_approval',
          'page': const ChangeApprovalScreen(),
        },
        {
          'label': _m('엑셀 데이타 일괄 관리\n(편집 잠금/해제, 구획 및 영수 번호 관리)'),
          'icon': Icons.table_view_outlined,
          'compactLabel': true,
          'page': const ExcelBulkManagementScreen(),
        },
        {
          'label': _m('할인 적용 관리'),
          'icon': Icons.percent_outlined,
          'menuKey': 'discount_management',
          'page': const DiscountManagementScreen(),
        },
        {
          'label': _m('시내.지방 배송 관리'),
          'icon': Icons.local_shipping_outlined,
          'menuKey': 'local_delivery_management',
          'page': const LocalDeliveryManagementScreen(),
        },
        {
          'label': _m('항차별 총액 관리'),
          'icon': Icons.analytics_outlined,
          'page': const VoyageTotalManagementScreen(),
        },
      ]);
    }

    if (_isAdmin || _isStaff) {
      items.addAll([
        {
          'label': _m('견적 요청 관리'),
          'icon': Icons.request_quote_outlined,
          'menuKey': 'quote_requests',
          'page': const QuoteRequestManagementScreen(),
        },
        {
          'label': _m('기준 환율 입력'),
          'icon': Icons.currency_exchange,
          'page': const ExchangeRateScreen(),
        },
      ]);
    }

    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: _loadStatus,
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
                  user.name.isEmpty ? _m('회원') : user.name,
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
            Text(
              _m('통합 관리'),
              style: const TextStyle(
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
              childAspectRatio: 2.35,
              children: items.map((item) {
                return OutlinedButton.icon(
                  onPressed: () => _openMenu(context, item),
                  icon: Icon(item['icon']! as IconData, size: 18),
                  label: _menuLabel(item),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
