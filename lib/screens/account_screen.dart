// lib/screens/account_screen.dart

import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';

// ---------------------------------------------------------------------------
// AccountScreen – thin Scaffold wrapper (keeps existing navigation compatible)
// ---------------------------------------------------------------------------

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.currentUser});

  final AppUser? currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AccountBody(currentUser: currentUser),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AccountBody – body-only widget (used by AppShell)
// ---------------------------------------------------------------------------

class AccountBody extends StatefulWidget {
  const AccountBody({
    super.key,
    this.currentUser,
    this.onLoggedIn,
    this.onLoggedOut,
    this.onOpenCargoManagement,
  });

  final AppUser? currentUser;
  final ValueChanged<AppUser>? onLoggedIn;
  final VoidCallback? onLoggedOut;
  final VoidCallback? onOpenCargoManagement;

  @override
  State<AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<AccountBody> {
  // ── Form ──────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberAccount = false;
  bool _rememberPassword = false;

  // ── Role selection ────────────────────────────────────────────────────────
  UserRole _selectedRole = UserRole.member;

  static const List<({String label, UserRole role})> _roleOptions = [
    (label: '일반 회원', role: UserRole.member),
    (label: '협력/파트너사', role: UserRole.partner),
    (label: '관리자', role: UserRole.admin),
  ];

  // ── Loading state ─────────────────────────────────────────────────────────
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
      ),
    );
  }

  // ── Mock login ────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('계정과 암호를 입력해 주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    // TODO(auth): replace mock with AuthController.instance.signIn(email, password)
    // e.g. await AuthController.instance.signIn(email: email, password: password);
    await Future.delayed(const Duration(milliseconds: 400));

    final mockUser = AppUser(
      id: 'mock-${DateTime.now().millisecondsSinceEpoch}',
      name: email.split('@').first,
      email: email,
      role: _selectedRole,
    );

    setState(() => _isLoading = false);

    widget.onLoggedIn?.call(mockUser);
    _showSnackBar('${mockUser.name}님, 환영합니다!');
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _handleLogout() async {
    // TODO(auth): await AuthController.instance.signOut();
    widget.onLoggedOut?.call();
    _showSnackBar('로그아웃 되었습니다.');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = widget.currentUser;
    final isLoggedIn = user != null && user.role != UserRole.guest;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: isLoggedIn ? _buildProfile(user) : _buildLoginForm(),
    );
  }

  // ── Login form ────────────────────────────────────────────────────────────

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Text(
            '계정 접속',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '서비스를 이용하려면 계정으로 접속하세요.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),

          // Role selector
          _buildRoleSelector(),
          const SizedBox(height: 24),

          // 계정 field
          _buildInputLabel('계정'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration(hint: '이메일 주소를 입력하세요'),
          ),
          const SizedBox(height: 16),

          // 암호 field
          _buildInputLabel('암호'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration(hint: '암호를 입력하세요').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textHint,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Checkboxes
          _buildCheckboxRow(
            label: '회원아이디 기억하기',
            value: _rememberAccount,
            onChanged: (v) => setState(() => _rememberAccount = v ?? false),
          ),
          const SizedBox(height: 4),
          _buildCheckboxRow(
            label: '암호 기억하기',
            value: _rememberPassword,
            onChanged: (v) => setState(() => _rememberPassword = v ?? false),
          ),
          const SizedBox(height: 28),

          // 접속 button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text(
                '접속',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 회원가입 button
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                // TODO(nav): navigate to registration screen
                _showSnackBar('회원가입 화면은 준비 중입니다.');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '회원가입',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Role selector ─────────────────────────────────────────────────────────

  Widget _buildRoleSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: _roleOptions.map((option) {
          final isSelected = _selectedRole == option.role;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedRole = option.role),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  option.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? AppColors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Profile view ──────────────────────────────────────────────────────────

  Widget _buildProfile(AppUser user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Avatar + name
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary,
                backgroundImage: user.avatarUrl != null
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                  user.name.isNotEmpty
                      ? user.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 28,
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                user.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user.email,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              _buildRoleBadge(user.role),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              if (user.phone != null) ...[
                _buildInfoRow(Icons.phone_outlined, '전화번호', user.phone!),
                const SizedBox(height: 10),
              ],
              if (user.company != null) ...[
                _buildInfoRow(
                    Icons.business_outlined, '소속', user.company!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Cargo management button (optional)
        if (widget.onOpenCargoManagement != null) ...[
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: widget.onOpenCargoManagement,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.inventory_2_outlined, size: 20),
              label: const Text(
                '화물 관리',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Logout button
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _handleLogout,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.logout, size: 20),
            label: const Text(
              '로그아웃',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
      filled: true,
      fillColor: AppColors.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _buildCheckboxRow({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(UserRole role) {
    final label = switch (role) {
      UserRole.admin => '관리자',
      UserRole.staff => '직원',
      UserRole.partner => '협력/파트너사',
      UserRole.member => '일반 회원',
      UserRole.guest => '비회원',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textHint),
        const SizedBox(width: 10),
        Text(
          '$title: ',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
