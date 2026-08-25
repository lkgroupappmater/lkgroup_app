// lib/screens/cargo_management_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';

class CargoManagementScreen extends StatefulWidget {
  const CargoManagementScreen({super.key, required this.user, this.onBack});
  final AppUser user;
  final VoidCallback? onBack;
  @override State<CargoManagementScreen> createState() => _CargoManagementScreenState();
}

class _CargoManagementScreenState extends State<CargoManagementScreen> {
  final _invoice = TextEditingController(), _name = TextEditingController(), _phone = TextEditingController(), _note = TextEditingController();
  DateTime? _enteredAt;
  @override void dispose() { for (final c in [_invoice, _name, _phone, _note]) { c.dispose(); } super.dispose(); }
  bool get _canManage => widget.user.role.canManageCargo;

  void _submit() {
    if (_invoice.text.trim().isEmpty) { _message('송장번호를 입력해 주세요.'); return; }
    final role = widget.user.role;
    if (role == UserRole.member) {
      _message('화물 정보 수정 요청이 접수되었습니다. 총괄 관리자 승인 후 반영됩니다.');
      // TODO: shipment_change_requests에 본인 화물 수정 요청을 insert하세요.
      return;
    }
    if (role == UserRole.staff && _enteredAt != null && DateTime.now().difference(_enteredAt!).inMinutes >= 10) {
      _message('입력 후 10분이 지나 수정 요청으로 등록되었습니다. 총괄 관리자 승인 후 반영됩니다.');
      // TODO: shipment_change_requests에 변경 내용을 저장하고 admin 승인을 기다리세요.
      return;
    }
    _enteredAt ??= DateTime.now();
    final message = role == UserRole.partner ? '협력/파트너사 권한으로 화물 정보가 저장되었습니다.' : '화물 정보가 저장되었습니다. 입력 후 10분 동안 직원 수정이 가능합니다.';
    _message(message);
    // TODO: 실제 운영 시 shipments insert/update를 Supabase에 연결하세요.
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: AppColors.primary));
  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(hintText: hint, prefixIcon: Icon(icon), filled: true, fillColor: AppColors.inputFill, border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(10)));

  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    if (widget.onBack != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back), label: const Text('계정으로 돌아가기'))),
    Card(color: AppColors.primary, child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(widget.user.name.isEmpty ? '회원' : widget.user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text(widget.user.roleLabel, style: const TextStyle(color: Colors.white70)))),
    const SizedBox(height: 16),
    Text(_canManage ? '선적별 정보 관리' : '내 화물 정보 수정 요청', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
    const SizedBox(height: 8),
    Text(widget.user.role == UserRole.partner ? '협력/파트너사는 화물 데이터를 항시 수정할 수 있습니다.' : widget.user.role == UserRole.staff ? '직원은 최초 입력 후 10분 이내 수정할 수 있으며 이후 총괄 관리자 승인이 필요합니다.' : '일반 회원은 본인 화물의 수정 요청만 등록할 수 있습니다.', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    const SizedBox(height: 14),
    TextField(controller: _invoice, decoration: _decoration('송장번호', Icons.receipt_long_outlined)), const SizedBox(height: 10),
    TextField(controller: _name, decoration: _decoration('이름/라오스 수령인', Icons.person_outline)), const SizedBox(height: 10),
    TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: _decoration('전화번호', Icons.phone_outlined)), const SizedBox(height: 10),
    TextField(controller: _note, maxLines: 4, decoration: _decoration('특이사항 또는 수정 내용', Icons.edit_note_outlined)), const SizedBox(height: 16),
    SizedBox(height: 48, child: ElevatedButton.icon(onPressed: _submit, icon: Icon(widget.user.role == UserRole.member ? Icons.send : Icons.save), label: Text(widget.user.role == UserRole.member ? '수정 요청 보내기' : '화물 정보 저장'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white))),
    const SizedBox(height: 22),
    if (widget.user.role.canEditSchedules || widget.user.role.canEditNotices) const Card(child: ListTile(leading: Icon(Icons.campaign_outlined), title: Text('일정·공지 관리'), subtitle: Text('직원과 총괄 관리자만 수정·추가할 수 있습니다.'))),
    if (widget.user.role.canApproveChanges) const Card(child: ListTile(leading: Icon(Icons.fact_check_outlined), title: Text('변경 요청 승인'), subtitle: Text('10분 이후 직원 수정 및 회원 요청을 승인합니다.'))),
  ]);
}
