// lib/screens/account_screen.dart

import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';

// ---------------------------------------------------------------------------
// Wrapper – keeps existing navigation code happy
// ---------------------------------------------------------------------------
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AccountBody();
  }
}

// ---------------------------------------------------------------------------
// Main body widget
// ---------------------------------------------------------------------------
class AccountBody extends StatefulWidget {
  const AccountBody({super.key, this.currentUser});

  final AppUser? currentUser;

  @override
  State<AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<AccountBody> {
  // ── controllers ──────────────────────────────────────────────────────────
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // ── state ─────────────────────────────────────────────────────────────────
  bool _obscurePassword = true;
  bool _rememberAccount = false;
  bool _rememberPassword = false;

  /// Display label → role string mapping (only three visible roles)
  static const List<String> _roleLabels = [
    '일반 회원',
    '관리자',
    '협력·파트너사',
  ];
  String _selectedRole = '일반 회원';

  // ── lifecycle ─────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Map the selected display label to the correct [UserRole].
  UserRole _resolveRole(String label) {
    if (label == '관리자') return UserRole.admin;
    if (label == '협력·파트너사') return UserRole.partner;
    return UserRole.member; // '일반 회원'
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
      ),
    );
  }

  // ── actions ───────────────────────────────────────────────────────────────

  void _onSignUp() {
    // TODO(auth): connect AuthController / Supabase sign-up flow here
    _showSnack('회원가입 기능은 준비 중입니다.');
  }

  void _onLogin() {
    final account = _accountController.text.trim();
    final password = _passwordController.text;

    if (account.isEmpty || password.isEmpty) {
      _showSnack('계정과 암호를 모두 입력해 주세요.');
      return;
    }

    // TODO(auth): replace mock below with real AuthController / Supabase login
    // Example:
    //   final result = await authController.signIn(
    //     email: account,
    //     password: password,
    //     role: _resolveRole(_selectedRole),
    //   );

    final resolvedRole = _resolveRole(_selectedRole);
    debugPrint('[AccountBody] mock login – role: $resolvedRole');

    _showSnack('접속이 완료되었습니다.');
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 32),
              _buildRoleSelector(),
              const SizedBox(height: 28),
              _buildAccountField(),
              const SizedBox(height: 16),
              _buildPasswordField(),
              const SizedBox(height: 12),
              _buildCheckboxes(),
              const SizedBox(height: 32),
              _buildButtons(),
            ],
          ),
        ),
      ),
    );
  }

  // ── sub-builders ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_outline_rounded,
            size: 36,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '회원 로그인',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '역할을 선택하고 계정 정보를 입력해 주세요.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRoleSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: _roleLabels.map((label) {
          final isSelected = label == _selectedRole;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedRole = label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                  isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

  Widget _buildAccountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('계정'),
        const SizedBox(height: 8),
        TextField(
          controller: _accountController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: _inputDecoration(
            hint: '이메일 또는 아이디',
            prefixIcon: Icons.person_outline,
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('암호'),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: _inputDecoration(
            hint: '암호를 입력하세요',
            prefixIcon: Icons.lock_outline,
          ).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppColors.textSecondary,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckboxes() {
    return Column(
      children: [
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
      ],
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
            side: BorderSide(color: AppColors.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 접속 (login) ──────────────────────────────────────────────────
        FilledButton(
          onPressed: _onLogin,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            '접속',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        // ── 회원가입 ──────────────────────────────────────────────────────
        OutlinedButton(
          onPressed: _onSignUp,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(50),
            side: BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            '회원가입',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ── tiny helpers ──────────────────────────────────────────────────────────

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
      prefixIcon: Icon(prefixIcon, color: AppColors.textSecondary, size: 20),
      filled: true,
      fillColor: AppColors.inputFill,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.6),
      ),
    );
  }
}
