// lib/screens/cargo_management_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';

/// 화물/입고 관리 body.
/// TODO: Supabase의 shipments, cargo_receivings, change_requests 테이블로 교체합니다.
class CargoManagementScreen extends StatefulWidget {
  const CargoManagementScreen({super.key, required this.user, this.onBack});
  final AppUser user;
  final VoidCallback? onBack;

  @override
  State<CargoManagementScreen> createState() => _CargoManagementScreenState();
}

class _CargoManagementScreenState extends State<CargoManagementScreen> {
  final _invoiceController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _invoiceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _isStaff => widget.user.role == UserRole.admin ||
      widget.user.role == UserRole.partner ||
      widget.user.role == UserRole.staff;

  void _submit(bool adminAction) {
    // TODO: insert into change_requests, then let an admin approve it.
    final message = adminAction
        ? '선적 정보 입력/수정 내용이 임시 저장되었습니다. (DB 연결 전)'
        : '회원 화물 정보 수정 요청이 접수되었습니다. 관리자 확인 후 반영됩니다.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('계정으로 돌아가기'),
            ),
          ),
        _RoleBanner(user: widget.user),
        const SizedBox(height: 14),
        _sectionTitle(_isStaff ? '선적별 정보 관리' : '내 화물 정보 수정 요청'),
        const SizedBox(height: 8),
        const Text(
          'DB 연동 전 임시 입력 화면입니다. 실제 운영 시 로그인한 회원은 본인 화물만 조회하고, 관리자·파트너사는 권한에 따라 선적 및 입고 정보를 관리합니다.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 14),
        _field(_invoiceController, '송장번호', Icons.receipt_long_outlined),
        const SizedBox(height: 10),
        _field(_nameController, '이름/수령인', Icons.person_outline),
        const SizedBox(height: 10),
        _field(_phoneController, '전화번호', Icons.phone_outlined, keyboardType: TextInputType.phone),
        const SizedBox(height: 10),
        _field(_noteController, '특이사항 또는 수정 요청 내용', Icons.edit_note_outlined, maxLines: 4),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () => _submit(_isStaff),
            icon: Icon(_isStaff ? Icons.save_outlined : Icons.send_outlined),
            label: Text(_isStaff ? '선적/입고 정보 저장' : '수정 요청 보내기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navyPrimary,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (_isStaff) ...[
          _sectionTitle('관리자·파트너사 기능'),
          const SizedBox(height: 8),
          _ActionTile(icon: Icons.fact_check_outlined, title: '회원 화물 정보 수정 요청', subtitle: '회원 요청 검토 및 승인/반려', onTap: () => _showComingSoon('회원 수정 요청 검토')),
          _ActionTile(icon: Icons.table_chart_outlined, title: '엑셀 데이터 업로드', subtitle: '업로드·열 매핑·검증 후 DB 반영', onTap: () => _showComingSoon('엑셀 업로드')),
          _ActionTile(icon: Icons.local_shipping_outlined, title: '선적별 입고 관리', subtitle: '선적 생성, 입고 등록, 상태 변경', onTap: () => _showComingSoon('선적별 입고 관리')),
        ],
      ],
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navyPrimary));

  Widget _field(TextEditingController controller, String hint, IconData icon, {TextInputType keyboardType = TextInputType.text, int maxLines = 1}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showComingSoon(String title) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: const Text('이 기능은 Supabase 테이블과 권한 정책을 연결할 때 활성화됩니다.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
      ),
    );
  }
}

class _RoleBanner extends StatelessWidget {
  const _RoleBanner({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
        child: Row(children: [
          const CircleAvatar(backgroundColor: AppColors.accent, child: Icon(Icons.person, color: Colors.white)),
          const SizedBox(width: 10),
          Expanded(child: Text('${user.name.isEmpty ? '회원' : user.name} · ${user.roleLabel}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navyPrimary))),
        ]),
      );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.cardBorder)),
        child: ListTile(leading: Icon(icon, color: AppColors.accent), title: Text(title), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap),
      );
}

