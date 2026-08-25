// lib/screens/account_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';

enum _AccountRole { general, admin, partner }

extension _RoleLabel on _AccountRole {
  String label(AppLanguage lang) {
    switch (this) {
      case _AccountRole.general:
        return lang == AppLanguage.english ? 'General Member' : lang == AppLanguage.lao ? 'ສະມາຊິກທົ່ວໄປ' : '일반 회원';
      case _AccountRole.admin:
        return lang == AppLanguage.english ? 'Administrator' : lang == AppLanguage.lao ? 'ຜູ້ດູແລລະບົບ' : '관리자';
      case _AccountRole.partner:
        return lang == AppLanguage.english ? 'Partner / Agent' : lang == AppLanguage.lao ? 'ຄູ່ຮ່ວມ / ຕົວແທນ' : '협력/파트너사';
    }
  }
}

class AccountBody extends StatefulWidget {
  // Compatibility parameters used by AppShell for login/logout and cargo navigation.
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
  _AccountRole _role = _AccountRole.general;
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _rememberAccount = false;
  bool _rememberPassword = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _login() {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정을 입력해 주세요.'), backgroundColor: AppColors.error),
      );
      return;
    }
    // TODO: Replace mock login with Supabase Auth and profiles lookup.
    final role = _role == _AccountRole.admin
        ? UserRole.admin
        : _role == _AccountRole.partner
            ? UserRole.partner
            : UserRole.member;
    widget.onLoggedIn?.call(AppUser(
      id: id,
      email: id.contains('@') ? id : '$id@example.com',
      name: id,
      phone: '연락처 미등록',
      company: '회사 정보 미등록',
      role: role,
    ));
  }

  void _signUp() {
    // TODO: Open Supabase sign-up/profile form.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('회원가입 화면 준비 중입니다.')),
    );
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
              onChanged: (r) => setState(() => _role = r),
            ),
            const SizedBox(height: 24),
            _field(_idCtrl, '계정', Icons.person_outline),
            const SizedBox(height: 12),
            TextField(
              controller: _pwCtrl,
              obscureText: _obscurePassword,
              decoration: _decoration('암호', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            _CheckRow(label: '회원아이디 기억하기', value: _rememberAccount, onChanged: (v) => setState(() => _rememberAccount = v ?? false)),
            _CheckRow(label: '암호 기억하기', value: _rememberPassword, onChanged: (v) => setState(() => _rememberPassword = v ?? false)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _signUp, child: const Text('회원가입'))),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: ElevatedButton(onPressed: _login, child: const Text('접속'))),
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

  Widget _field(TextEditingController controller, String hint, IconData icon) {
    return TextField(controller: controller, decoration: _decoration(hint, icon));
  }

  InputDecoration _decoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
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
                  const CircleAvatar(radius: 35, backgroundColor: AppColors.white, child: Text('🧸', style: TextStyle(fontSize: 34))),
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
          const _InfoTile(Icons.calendar_month_outlined, '서비스 이용 빈도', '이용 기록을 준비 중입니다'),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.cardBorder)),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: AppColors.navyPrimary),
        title: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        subtitle: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('역할 선택', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: _AccountRole.values
              .map(
                (r) => Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(r),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected == r ? AppColors.navyPrimary : AppColors.inputFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        r.label(language),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: selected == r ? AppColors.white : AppColors.textSecondary),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
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
