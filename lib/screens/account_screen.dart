import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/app_user.dart';

/// Body-only account tab. AppShell owns the main Scaffold and AppBar.
class AccountBody extends StatefulWidget {
  const AccountBody({super.key, this.currentUser, this.onLoggedIn, this.onLoggedOut});
  final AppUser? currentUser;
  final ValueChanged<AppUser>? onLoggedIn;
  final VoidCallback? onLoggedOut;
  @override State<AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<AccountBody> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _rememberAccount = false;
  bool _rememberPassword = false;
  UserRole _role = UserRole.member;

  @override
  void dispose() { _account.dispose(); _password.dispose(); super.dispose(); }

  void _message(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  void _login() {
    final account = _account.text.trim();
    if (account.isEmpty || _password.text.isEmpty) {
      _message('계정과 암호를 입력해 주세요.');
      return;
    }
    // TODO(supabase): replace this mock with AuthService/Supabase Auth.
    widget.onLoggedIn?.call(AppUser(id: account, email: account, name: '회원', role: _role));
    _message('접속이 완료되었습니다.');
  }

  void _signUp() {
    final account = TextEditingController();
    final password = TextEditingController();
    final name = TextEditingController();
    UserRole role = UserRole.member;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('회원가입'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dialogField(account, '계정'),
            _dialogField(password, '암호', obscure: true),
            _dialogField(name, '이름'),
            DropdownButtonFormField<UserRole>(
              value: role,
              decoration: const InputDecoration(labelText: '회원 유형'),
              items: const [
                DropdownMenuItem(value: UserRole.member, child: Text('일반 회원')),
                DropdownMenuItem(value: UserRole.partner, child: Text('협력/파트너사')),
              ],
              onChanged: (value) { if (value != null) setDialogState(() => role = value); },
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
            FilledButton(
              onPressed: () {
                if (account.text.trim().isEmpty || password.text.isEmpty || name.text.trim().isEmpty) {
                  _message('계정, 암호, 이름을 입력해 주세요.');
                  return;
                }
                // TODO(supabase): auth.signUp and profiles insert/approval flow.
                Navigator.pop(dialogContext);
                _message('회원가입 요청이 접수되었습니다.');
              },
              child: const Text('가입 신청'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogField(TextEditingController controller, String label, {bool obscure = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(controller: controller, obscureText: obscure, decoration: InputDecoration(
      labelText: label, filled: true, fillColor: AppColors.inputFill,
      border: const OutlineInputBorder(),
    )),
  );

  @override
  Widget build(BuildContext context) {
    final user = widget.currentUser;
    if (user != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text(user.name.isEmpty ? '회원' : user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)),
        ListTile(title: const Text('계정'), subtitle: Text(user.email)),
        ListTile(title: const Text('권한'), subtitle: Text(user.roleLabel)),
        OutlinedButton(onPressed: widget.onLoggedOut, child: const Text('로그아웃')),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(20), children: [
      SegmentedButton<UserRole>(
        segments: const [
          ButtonSegment(value: UserRole.member, label: Text('일반 회원')),
          ButtonSegment(value: UserRole.admin, label: Text('관리자')),
          ButtonSegment(value: UserRole.partner, label: Text('협력/파트너사')),
        ],
        selected: {_role},
        onSelectionChanged: (value) { if (value.isNotEmpty) setState(() => _role = value.first); },
      ),
      const SizedBox(height: 18),
      TextField(controller: _account, decoration: const InputDecoration(labelText: '계정', prefixIcon: Icon(Icons.person_outline), filled: true, fillColor: AppColors.inputFill, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _password, obscureText: _obscure, decoration: InputDecoration(labelText: '암호', prefixIcon: const Icon(Icons.lock_outline), filled: true, fillColor: AppColors.inputFill, border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
      CheckboxListTile(value: _rememberAccount, onChanged: (value) => setState(() => _rememberAccount = value ?? false), title: const Text('회원아이디 기억하기'), contentPadding: EdgeInsets.zero),
      CheckboxListTile(value: _rememberPassword, onChanged: (value) => setState(() => _rememberPassword = value ?? false), title: const Text('암호 기억하기'), contentPadding: EdgeInsets.zero),
      FilledButton(onPressed: _login, child: const Text('접속')),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _signUp, child: const Text('회원가입')),
    ]);
  }
}

/// Compatibility wrapper for code that still uses AccountScreen directly.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.currentUser});
  final AppUser? currentUser;
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(child: AccountBody(currentUser: currentUser)),
  );
}
