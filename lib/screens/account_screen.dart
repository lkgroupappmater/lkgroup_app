// lib/screens/account_screen.dart
import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

enum _AccountRole { general, admin, partner }

extension _AccountRoleText on _AccountRole {
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

/// AppShell의 계정 탭에서 사용하는 본문입니다.
/// 실제 인증은 AuthService의 Supabase 교체 지점에 연결합니다.
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
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  _AccountRole _role = _AccountRole.general;
  bool _rememberAccount = false;
  bool _rememberPassword = false;
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (account.isEmpty || password.isEmpty) {
      _message('계정과 암호를 입력해 주세요.', error: true);
      return;
    }

    setState(() => _loading = true);
    try {
      // TODO: AuthService.signIn 내부 mock을 Supabase Auth로 교체하세요.
      // 역할은 화면 선택값이 아니라 profiles.role과 RLS 정책으로 검증해야 합니다.
      final user = await AuthService.instance.signIn(
        email: account,
        password: password,
      );
      if (!mounted) return;
      widget.onLoggedIn?.call(user);
      _message('접속이 완료되었습니다.');
    } on AuthException catch (error) {
      if (mounted) _message(error.message, error: true);
    } catch (_) {
      if (mounted) _message('접속 중 오류가 발생했습니다.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _signUp() {
    // TODO: Supabase Auth signUp() 후 profiles 테이블을 생성/저장하세요.
    _message('회원가입 화면 준비 중입니다.');
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : AppColors.navyPrimary,
      ),
    );
  }

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RoleSelector(
              selected: _role,
              language: widget.language,
              onChanged: (value) => setState(() => _role = value),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _accountController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: _decoration('계정', Icons.person_outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
              decoration: _decoration('암호', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '암호 보이기' : '암호 숨기기',
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                ),
              ),
            ),
            _CheckRow(
              label: '회원아이디 기억하기',
              value: _rememberAccount,
              onChanged: (value) => setState(() => _rememberAccount = value),
            ),
            _CheckRow(
              label: '암호 기억하기',
              value: _rememberPassword,
              onChanged: (value) => setState(() => _rememberPassword = value),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : _signUp,
                    child: const Text('회원가입'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('접속'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
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
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({
    required this.selected,
    required this.language,
    required this.onChanged,
  });

  final _AccountRole selected;
  final AppLanguage language;
  final ValueChanged<_AccountRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '역할 선택',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _AccountRole.values.map((role) {
            final selectedRole = role == selected;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onChanged(role),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: selectedRole
                          ? AppColors.navyPrimary
                          : AppColors.inputFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      role.label(language),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: selectedRole
                            ? AppColors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Checkbox(
            value: value,
            activeColor: AppColors.navyPrimary,
            onChanged: (next) => onChanged(next ?? false),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoggedInProfile extends StatelessWidget {
  const _LoggedInProfile({
    required this.user,
    this.onLogout,
    this.onOpenCargoManagement,
  });

  final AppUser user;
  final VoidCallback? onLogout;
  final VoidCallback? onOpenCargoManagement;

  @override
  Widget build(BuildContext context) {
    final name = user.name.trim().isEmpty ? user.id : user.name;
    final email = user.email.trim().isEmpty ? '메일 미등록' : user.email;
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: AppColors.white,
                    child: Icon(
                      Icons.person,
                      size: 38,
                      color: AppColors.navyPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${user.roleLabel} · $company',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '회원 정보',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _InfoTile(Icons.person_outline, '이름', name),
          _InfoTile(Icons.phone_outlined, '연락처', phone),
          _InfoTile(Icons.email_outlined, '메일', email),
          const _InfoTile(
            Icons.location_on_outlined,
            '주소',
            '주소 정보 미등록',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onOpenCargoManagement,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('화물/입고 관리'),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('로그아웃'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
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
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 기존 라우트와의 호환용 wrapper입니다.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    this.language = AppLanguage.korean,
    this.currentUser,
  });

  final AppLanguage language;
  final AppUser? currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AccountBody(
        language: language,
        currentUser: currentUser,
      ),
    );
  }
}
