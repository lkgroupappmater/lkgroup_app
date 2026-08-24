// lib/screens/account_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';

// ---------------------------------------------------------------------------
// Account roles
// ---------------------------------------------------------------------------
enum _AccountRole { general, admin, partner }

extension _RoleLabel on _AccountRole {
  String label(AppLanguage lang) {
    switch (this) {
      case _AccountRole.general:
        switch (lang) {
          case AppLanguage.english: return 'General Member';
          case AppLanguage.lao: return 'ສະມາຊິກທົ່ວໄປ';
          default:             return '일반 회원';
        }
      case _AccountRole.admin:
        switch (lang) {
          case AppLanguage.english: return 'Administrator';
          case AppLanguage.lao: return 'ຜູ້ດູແລລະບົບ';
          default:             return '관리자';
        }
      case _AccountRole.partner:
        switch (lang) {
          case AppLanguage.english: return 'Partner / Agent';
          case AppLanguage.lao: return 'ຄູ່ຮ່ວມ / ຕົວແທນ';
          default:             return '협력/파트너사';
        }
    }
  }
}

// ---------------------------------------------------------------------------
// Body-only widget
// ---------------------------------------------------------------------------
class AccountBody extends StatefulWidget {
  const AccountBody({
    super.key,
    this.language = AppLanguage.korean,
    this.currentUser,
    this.onLoggedIn,
    this.onOpenCargoManagement,
  });
  final AppLanguage language;
  final AppUser? currentUser;
  final ValueChanged<AppUser>? onLoggedIn;
  final VoidCallback? onOpenCargoManagement;

  @override
  State<AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<AccountBody> {
  _AccountRole _role = _AccountRole.general;
  final _idCtrl   = TextEditingController();
  final _pwCtrl   = TextEditingController();
  bool _rememberAccount = false;
  bool _rememberPassword = false;
  bool _obscurePw = true;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _login() {
    // TODO: Connect to real AuthController / Auth API.
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('계정을 입력해 주세요.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final user = AppUser(
      id: id,
      email: id,
      name: id,
      phone: '',
      company: '',
      role: _role == _AccountRole.admin
          ? UserRole.admin
          : _role == _AccountRole.partner
              ? UserRole.partner
              : UserRole.member,
    );
    if (widget.onLoggedIn != null) {
      widget.onLoggedIn!(user);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('[$id] 접속 중... (mock)'),
        backgroundColor: AppColors.navyPrimary,
      ),
    );
  }

  void _signUp() {
    // TODO: Connect to sign-up screen / API.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('회원가입 화면 준비 중입니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // Role selector
            _RoleSelector(
              selected: _role,
              language: lang,
              onChanged: (r) => setState(() => _role = r),
            ),
            const SizedBox(height: 24),

            // Account input
            _buildField(
              controller: _idCtrl,
              hint: '계정',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),

            // Password input
            TextField(
              controller: _pwCtrl,
              obscureText: _obscurePw,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '암호',
                hintStyle: const TextStyle(
                    color: AppColors.textHint, fontSize: 13),
                prefixIcon: const Icon(Icons.lock_outline,
                    size: 20, color: AppColors.textSecondary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePw
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePw = !_obscurePw),
                ),
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(
                      color: AppColors.accent, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
              ),
            ),
            const SizedBox(height: 8),

            // Checkboxes
            _CheckRow(
              label: '회원아이디 기억하기',
              value: _rememberAccount,
              onChanged: (v) =>
                  setState(() => _rememberAccount = v ?? false),
            ),
            _CheckRow(
              label: '암호 기억하기',
              value: _rememberPassword,
              onChanged: (v) =>
                  setState(() => _rememberPassword = v ?? false),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _signUp,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyPrimary,
                      side: const BorderSide(
                          color: AppColors.navyPrimary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('회원가입',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyPrimary,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('접속',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),

            if (widget.currentUser != null && widget.onOpenCargoManagement != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: widget.onOpenCargoManagement,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('화물/입고 관리'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navyPrimary,
                  side: const BorderSide(color: AppColors.navyPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
            const SizedBox(height: 32),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 16),

            // Footer hint
            const Center(
              child: Text(
                '문제가 있으신가요? 카카오톡 또는 WhatsApp으로 연락해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(
          fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
        const TextStyle(color: AppColors.textHint, fontSize: 13),
        prefixIcon: Icon(icon,
            size: 20, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide:
          const BorderSide(color: AppColors.accent, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role selector
// ---------------------------------------------------------------------------
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
        const Text('역할 선택',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: _AccountRole.values.map((role) {
            final active = selected == role;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(role),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.navyPrimary
                        : AppColors.inputFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active
                          ? AppColors.navyPrimary
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Text(
                    role.label(language),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.white
                          : AppColors.textSecondary,
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

// ---------------------------------------------------------------------------
// Checkbox row
// ---------------------------------------------------------------------------
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: value,
          activeColor: AppColors.navyPrimary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged,
        ),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Legacy wrapper
// ---------------------------------------------------------------------------
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.language = AppLanguage.korean});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyPrimary,
        foregroundColor: AppColors.white,
        title: Text(AppStrings.get(language, 'account'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: AccountBody(language: language),
    );
  }
}








