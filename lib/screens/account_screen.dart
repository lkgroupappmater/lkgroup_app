// lib/screens/account_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';

enum _AccountRole { general, admin, partner }

extension _RoleLabel on _AccountRole {
  String label(AppLanguage language) {
    switch (this) {
      case _AccountRole.general:
        if (language == AppLanguage.english) return 'General Member';
        if (language == AppLanguage.lao) return 'ສະມາຊິກທົ່ວໄປ';
        return '일반 회원';
      case _AccountRole.admin:
        if (language == AppLanguage.english) return 'Administrator';
        if (language == AppLanguage.lao) return 'ຜູ້ດູແລລະບົບ';
        return '관리자';
      case _AccountRole.partner:
        if (language == AppLanguage.english) return 'Partner / Agent';
        if (language == AppLanguage.lao) return 'ຄູ່ຮ່ວມ / ຕົວແທນ';
        return '협력/파트너사';
    }
  }
}

class AccountBody extends StatefulWidget {
  const AccountBody({
    super.key,
    this.language = AppLanguage.korean,
    this.currentUser,
    this.onLoggedIn,
    this.onLoggedOut,
    this.onOpenCargoManagement,
  });

  final AppLanguage language;
  final AppUser? currentUser;
  final ValueChanged<AppUser>? onLoggedIn;
  final VoidCallback? onLoggedOut;
  final VoidCallback? onOpenCargoManagement;

  @override
  State<AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<AccountBody> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  _AccountRole _role = _AccountRole.general;
  bool _rememberAccount = false;
  bool _rememberPassword = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      _showMessage('계정을 입력해 주세요.', isError: true);
      return;
    }

    // TODO: Replace this mock with Supabase Auth signInWithPassword().
    final role = _role == _AccountRole.admin
        ? UserRole.admin
        : _role == _AccountRole.partner
            ? UserRole.partner
            : UserRole.member;
    final email = id.contains('@') ? id : '$id@example.com';
    widget.onLoggedIn?.call(AppUser(
      id: id,
      email: email,
      name: id,
      phone: '연락처 미등록',
      company: '회사 정보 미등록',
      role: role,
    ));
    _showMessage('접속이 완료되었습니다.');
  }

  void _signUp() {
    // TODO: Replace with Supabase Auth signUp() and profile creation.
    _showMessage('회원가입 화면 준비 중입니다.');
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : AppColors.navyPrimary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.currentUser;
    if (user != null && user.role.isLoggedIn) {
      return _LoggedInProfile(
        user: user,
        onLogout: widget.onLoggedOut,
        onOpenCargoManagement: widget.onOpenCargoManagement,
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _RoleSelector(
              selected: _role,
              language: widget.language,
              onChanged: (role) => setState(() => _role = role),
            ),
            const SizedBox(height: 24),
            _input('계정', Icons.person_outline, _idController),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _hidePassword,
              decoration: _inputDecoration('암호', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_hidePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                ),
              ),
            ),
            _CheckRow(
              label: '회원아이디 기억하기',
              value: _rememberAccount,
              onChanged: (value) => setState(() => _rememberAccount = value ?? false),
            ),
            _CheckRow(
              label: '암호 기억하기',
              value: _rememberPassword,
              onChanged: (value) => setState(() => _rememberPassword = value ?? false),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _signUp, child: const Text('회원가입'))),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(onPressed: _login, child: const Text('접속')),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 14),
            const Text(
              '문제가 있으신가요? 카카오톡 또는 WhatsApp으로 연락해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(String hint, IconData icon, TextEditingController controller) {
    return TextField(controller: controller, decoration: _inputDecoration(hint, icon));
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.selected, required this.language, required this.onChanged});

  final _AccountRole selected;
  final AppLanguage language;
  final ValueChanged<_AccountRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final buttons = _AccountRole.values.map<Widget>((role) {
      final selectedRole = selected == role;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(role),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selectedRole ? AppColors.navyPrimary : AppColors.inputFill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              role.label(language),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: selectedRole ? AppColors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '역할 선택',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Row(children: buttons),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: value, activeColor: AppColors.navyPrimary, onChanged: onChanged),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _LoggedInProfile extends StatelessWidget {
  const _LoggedInProfile({required this.user, this.onLogout, this.onOpenCargoManagement});

  final AppUser user;
  final VoidCallback? onLogout;
  final VoidCallback? onOpenCargoManagement;

  @override
  Widget build(BuildContext context) {
    final name = user.name.trim().isEmpty ? user.id : user.name;
    final email = user.email.trim().isEmpty ? '${user.id}@example.com' : user.email;
    final phone = user.phone.trim().isEmpty ? '연락처 미등록' : user.phone;
    final company = user.company.trim().isEmpty ? '회사 정보 미등록' : user.company;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: AppColors.navyPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: AppColors.white,
                    child: Text('🧸', style: TextStyle(fontSize: 34)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: AppColors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('${user.roleLabel} · $company', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('회원 정보', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          _InfoTile(Icons.person_outline, '이름', name),
          _InfoTile(Icons.phone_outlined, '연락처', phone),
          _InfoTile(Icons.email_outlined, '메일', email),
          const _InfoTile(Icons.location_on_outlined, '주소', '주소 정보 미등록'),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: onOpenCargoManagement, icon: const Icon(Icons.inventory_2_outlined), label: const Text('화물/입고 관리')),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('로그아웃'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: AppColors.white),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: AppColors.navyPrimary),
        title: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        subtitle: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.language = AppLanguage.korean});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AccountBody(language: language),
    );
  }
}
