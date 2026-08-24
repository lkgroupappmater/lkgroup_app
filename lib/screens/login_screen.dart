// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_inherited_notifier.dart';
import '../services/auth_service.dart';
import '../models/app_user.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── 색상 상수 ─────────────────────────────────────────────────────────────
  static const _navy = Color(0xFF0D1B3E);
  static const _navyLight = Color(0xFF1A2F5A);
  static const _teal = Color(0xFF00B4D8);
  static const _tealDark = Color(0xFF0096C7);
  static const _surface = Color(0xFFF0F4F8);

  // ── 로그인 처리 ──────────────────────────────────────────────────────────
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final ctrl = AuthControllerScope.read(context);
    final success = await ctrl.signIn(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    if (!mounted) return;

    if (!success) {
      final msg = ctrl.errorMessage ?? '로그인에 실패했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(msg)),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    // 성공 시 app.dart 의 ListenableBuilder 가 자동으로 AppShell 로 전환합니다.
  }

  // ── 게스트 진행 ──────────────────────────────────────────────────────────
  void _handleGuest() {
    AuthControllerScope.read(context).browseAsGuest();
  }

  // ── 데모 계정 자동 채우기 ────────────────────────────────────────────────
  void _fillDemo(MockAccountInfo info) {
    _emailCtrl.text = info.email;
    _passwordCtrl.text = info.password;
  }

  // ── 역할 색상 ─────────────────────────────────────────────────────────────
  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:   return Colors.deepPurple;
      case UserRole.partner: return Colors.orange.shade700;
      case UserRole.member:  return _tealDark;
      default:               return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ListenableBuilder(
            listenable: AuthControllerScope.of(context),
            builder: (context, _) {
              final ctrl = AuthControllerScope.of(context);
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    _buildLogo(),
                    const SizedBox(height: 40),
                    _buildForm(ctrl),
                    const SizedBox(height: 24),
                    _buildDemoCard(),
                    const SizedBox(height: 20),
                    _buildGuestButton(ctrl),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── 로고 ─────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _teal,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _teal.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.local_shipping_rounded,
              size: 44, color: Colors.white),
        ),
        const SizedBox(height: 16),
        const Text(
          'CargoFlow',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '무역·운송 통합 관리 플랫폼',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.6),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ── 로그인 폼 ─────────────────────────────────────────────────────────────
  Widget _buildForm(AuthController ctrl) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _navyLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '로그인',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.95),
              ),
            ),
            const SizedBox(height: 24),

            // 이메일
            _buildTextField(
              controller: _emailCtrl,
              label: '이메일',
              hint: 'example@cargoflow.dev',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '이메일을 입력해주세요.';
                if (!v.contains('@')) return '올바른 이메일 형식이 아닙니다.';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 비밀번호
            _buildTextField(
              controller: _passwordCtrl,
              label: '비밀번호',
              hint: '비밀번호 입력',
              icon: Icons.lock_outline,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white54,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return '비밀번호를 입력해주세요.';
                if (v.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
                return null;
              },
              onFieldSubmitted: (_) => ctrl.isLoading ? null : _handleLogin(),
            ),

            // 에러 메시지
            if (ctrl.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.red.shade400.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade300, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ctrl.errorMessage!,
                        style: TextStyle(
                            color: Colors.red.shade200, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 로그인 버튼
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: ctrl.isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _teal.withOpacity(0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: ctrl.isLoading
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  '로그인',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),

            // [SUPABASE] 비밀번호 재설정 링크 추가 지점:
            // const SizedBox(height: 12),
            // TextButton(
            //   onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
            //   child: Text('비밀번호를 잊으셨나요?'),
            // ),

            // [SUPABASE] 회원가입 링크 추가 지점:
            // const SizedBox(height: 8),
            // TextButton(
            //   onPressed: () => Navigator.pushNamed(context, '/register'),
            //   child: Text('계정이 없으신가요? 회원가입'),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3),
            fontSize: 13),
        labelStyle:
        TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
        prefixIcon:
        Icon(icon, color: Colors.white.withOpacity(0.5), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _teal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
        errorStyle: TextStyle(color: Colors.red.shade300, fontSize: 12),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ── 데모 계정 카드 ────────────────────────────────────────────────────────
  Widget _buildDemoCard() {
    final demos = AuthService.demoAccounts;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _teal.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: _teal, size: 16),
              const SizedBox(width: 6),
              const Text(
                '데모 계정 (탭하면 자동 입력)',
                style: TextStyle(
                  color: _teal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...demos.map((info) => _buildDemoTile(info)),
        ],
      ),
    );
  }

  Widget _buildDemoTile(MockAccountInfo info) {
    return GestureDetector(
      onTap: () => _fillDemo(info),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _roleColor(info.role).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _roleColor(info.role).withOpacity(0.5)),
              ),
              child: Text(
                info.label,
                style: TextStyle(
                  color: _roleColor(info.role),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.email,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'PW: ${info.password}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.touch_app_outlined,
                color: Colors.white.withOpacity(0.3), size: 16),
          ],
        ),
      ),
    );
  }

  // ── 게스트 버튼 ───────────────────────────────────────────────────────────
  Widget _buildGuestButton(AuthController ctrl) {
    return OutlinedButton.icon(
      onPressed: ctrl.isLoading ? null : _handleGuest,
      icon: Icon(Icons.explore_outlined,
          size: 18, color: Colors.white.withOpacity(0.7)),
      label: Text(
        '비로그인으로 둘러보기',
        style:
        TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}


