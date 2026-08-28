import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.currentUser});
  final AppUser? currentUser;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: AccountBody(currentUser: currentUser)),
      );
}

class AccountBody extends StatefulWidget {
  const AccountBody({
    super.key,
    this.currentUser,
    this.onLoggedIn,
    this.onLoggedOut,
  });

  final AppUser? currentUser;
  final ValueChanged<AppUser>? onLoggedIn;
  final VoidCallback? onLoggedOut;

  @override
  State<AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<AccountBody> {
  final _account = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _rememberAccount = false;
  bool _rememberPassword = false;
  String _avatar = '🙂';

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openSignup() async {
    final result = await showDialog<_SignupResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SignupDialog(),
    );

    if (result == null || !mounted) return;

    try {
      final authResult = await AuthService.instance.signUp(
        email: result.email,
        password: result.password,
        name: result.name,
        phone: result.phone,
        company: result.company,
        role: result.role,
        verificationMethod: 'email',
      );

      if (!mounted) return;
      if (result.role == UserRole.member) {
        _message(authResult.emailConfirmationRequired
            ? '회원가입이 완료되었습니다. 이메일 인증 후 접속해 주세요.'
            : '회원가입이 완료되었습니다. 바로 접속할 수 있습니다.');
      } else {
        _message(
            '${_signupRoleLabel(result.role)} 가입 신청이 완료되었습니다. 총괄 관리자 승인 후 접속할 수 있습니다.');
      }
    } catch (error) {
      _message('회원가입 실패: $error');
    }
  }

  Future<void> _login() async {
    if (_account.text.trim().isEmpty || _password.text.isEmpty) {
      _message('계정과 암호를 입력해 주세요.');
      return;
    }
    try {
      final user = await AuthService.instance.signIn(
        email: _account.text.trim(),
        password: _password.text,
      );
      if (mounted) widget.onLoggedIn?.call(user);
    } catch (error) {
      if (mounted) _message('접속 실패: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.currentUser != null) ...[
          _profile(),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: widget.onLoggedOut,
            child: const Text('로그아웃'),
          ),
        ] else ...[
          TextField(
            controller: _account,
            decoration: const InputDecoration(
              labelText: '계정',
              prefixIcon: Icon(Icons.person_outline),
              filled: true,
              fillColor: AppColors.inputFill,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '암호',
              prefixIcon: const Icon(Icons.lock_outline),
              filled: true,
              fillColor: AppColors.inputFill,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
              ),
            ),
          ),
          _check(
            '회원아이디 기억하기',
            _rememberAccount,
            (value) => setState(() => _rememberAccount = value),
          ),
          _check(
            '암호 기억하기',
            _rememberPassword,
            (value) => setState(() => _rememberPassword = value),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _login,
            child: const Text('접속'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _openSignup,
            child: const Text('회원가입'),
          ),
        ],
      ],
    );
  }

  Widget _check(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      CheckboxListTile(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        title: Text(label),
        contentPadding: EdgeInsets.zero,
        dense: true,
      );

  Widget _profile() {
    final user = widget.currentUser!;
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.inputFill,
              child: Text(_avatar, style: const TextStyle(fontSize: 42)),
            ),
            PopupMenuButton<String>(
              icon:
                  const Icon(Icons.camera_alt, color: AppColors.primary),
              onSelected: (v) {
                if (v == 'camera') _message('카메라 연결 위치입니다.');
                if (v == 'photo') _message('사진 선택 연결 위치입니다.');
                if (v == 'character') {
                  setState(() => _avatar = '🐼');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'camera', child: Text('카메라')),
                PopupMenuItem(value: 'photo', child: Text('사진 선택')),
                PopupMenuItem(
                    value: 'character', child: Text('귀여운 캐릭터 선택')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          user.name.isEmpty ? '회원' : user.name,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Chip(label: Text(_profileRoleLabel(user.role))),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _info('전화번호', user.phone),
              _info('그룹', _profileRoleLabel(user.role)),
              _info('주소', user.address),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _message('회원 정보 변경 화면 연결 위치입니다.'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('회원 정보 변경'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _message('암호 변경 화면 연결 위치입니다.'),
                icon: const Icon(Icons.lock_outline),
                label: const Text('암호 변경'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _info(String label, String value) => ListTile(
        title: Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        subtitle: Text(value.isEmpty ? '등록되지 않음' : value),
      );

  static String _profileRoleLabel(UserRole role) => switch (role) {
        UserRole.admin => '관리자(총괄)',
        UserRole.staff => '관리자(직원)',
        UserRole.partner => '협력/파트너사',
        _ => '일반 회원',
      };

  static String _signupRoleLabel(UserRole role) => switch (role) {
        UserRole.admin => '관리자',
        UserRole.partner => '협력/파트너사',
        _ => '일반 회원',
      };
}

class _SignupDialog extends StatefulWidget {
  const _SignupDialog();

  @override
  State<_SignupDialog> createState() => _SignupDialogState();
}

class _SignupDialogState extends State<_SignupDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();

  UserRole _role = UserRole.member;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _phone.dispose();
    _company.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _passwordConfirm.text.isEmpty) {
      _show('이름, 이메일, 암호, 암호확인을 입력해 주세요.');
      return;
    }
    if (_password.text != _passwordConfirm.text) {
      _show('암호와 암호확인이 일치하지 않습니다.');
      return;
    }

    Navigator.pop(
      context,
      _SignupResult(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        phone: _phone.text.trim(),
        company: _company.text.trim(),
        role: _role,
      ),
    );
  }

  void _show(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('회원 가입'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: '이름')),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '이메일'),
              ),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '암호'),
              ),
              TextField(
                controller: _passwordConfirm,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: '암호확인'),
              ),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: '전화번호'),
              ),
              TextField(
                controller: _company,
                decoration:
                    const InputDecoration(labelText: '회사명(선택)'),
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '협력/파트너사 및 관리자는 총괄 관리자 승인이 필요 합니다.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(
                    value: UserRole.member,
                    label: Text('일반회원'),
                  ),
                  ButtonSegment(
                    value: UserRole.admin,
                    label: Text('관리자'),
                  ),
                  ButtonSegment(
                    value: UserRole.partner,
                    label: Text('협력/파트너사'),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (value) {
                  setState(() => _role = value.first);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('가입하기'),
          ),
        ],
      );
}

class _SignupResult {
  const _SignupResult({
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
    required this.company,
    required this.role,
  });

  final String name;
  final String email;
  final String password;
  final String phone;
  final String company;
  final UserRole role;
}
