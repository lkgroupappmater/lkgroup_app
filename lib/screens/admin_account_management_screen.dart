// lib/screens/admin_account_management_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AdminAccountManagementScreen extends StatefulWidget {
  const AdminAccountManagementScreen({super.key});
  @override
  State<AdminAccountManagementScreen> createState() =>
      _AdminAccountManagementScreenState();
}

class _AdminAccountManagementScreenState
    extends State<AdminAccountManagementScreen> {
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _company = TextEditingController(),
      _phone = TextEditingController();
  UserRole _role = UserRole.staff;
  bool _loading = false;
  @override
  void dispose() {
    for (final c in [_name, _email, _company, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이름과 이메일을 입력해 주세요.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.requestStaffOrPartnerAccount(
          AccountProvisionRequest(
              name: _name.text.trim(),
              email: _email.text.trim(),
              role: _role,
              company: _company.text.trim(),
              phone: _phone.text.trim()));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('계정 발급 요청이 등록되었습니다.')));
        _name.clear();
        _email.clear();
        _company.clear();
        _phone.clear();
      }
    } on AuthException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _input(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(10)));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('계정 가입 및 관리')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('총괄 관리자 전용',
            style:
                TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            '일반 회원은 앱에서 직접 가입합니다. 직원·협력/파트너사 계정은 여기서 발급 요청을 등록하고, 실제 Auth 계정 생성은 보안 서버/Edge Function에서 처리하세요.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 18),
        DropdownButtonFormField<UserRole>(
            value: _role,
            decoration: _input('계정 유형'),
            items: const [
              DropdownMenuItem(value: UserRole.staff, child: Text('관리자(직원)')),
              DropdownMenuItem(value: UserRole.partner, child: Text('협력/파트너사'))
            ],
            onChanged: (v) => setState(() => _role = v ?? UserRole.staff)),
        const SizedBox(height: 10),
        TextField(controller: _name, decoration: _input('이름')),
        const SizedBox(height: 10),
        TextField(controller: _email, decoration: _input('이메일')),
        const SizedBox(height: 10),
        TextField(controller: _company, decoration: _input('회사명')),
        const SizedBox(height: 10),
        TextField(controller: _phone, decoration: _input('연락처')),
        const SizedBox(height: 18),
        SizedBox(
            height: 48,
            child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('가입/발급 요청 등록'))),
        const SizedBox(height: 28),
        const Card(
            child: ListTile(
                leading: Icon(Icons.security),
                title: Text('권한 적용 원칙'),
                subtitle: Text('권한은 profiles.role과 Supabase RLS로 서버에서 강제합니다.')))
      ]));
}
