import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AccountScreen extends StatelessWidget { const AccountScreen({super.key, this.currentUser}); final AppUser? currentUser; @override Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, body: SafeArea(child: AccountBody(currentUser: currentUser))); }
class AccountBody extends StatefulWidget { const AccountBody({super.key, this.currentUser, this.onLoggedIn, this.onLoggedOut}); final AppUser? currentUser; final ValueChanged<AppUser>? onLoggedIn; final VoidCallback? onLoggedOut; @override State<AccountBody> createState() => _AccountBodyState(); }
class _AccountBodyState extends State<AccountBody> {
  final _account = TextEditingController(), _password = TextEditingController(), _name = TextEditingController(), _phone = TextEditingController(), _group = TextEditingController(), _address = TextEditingController(); bool _obscure = true, _rememberAccount = false, _rememberPassword = false; UserRole _role = UserRole.member; String _avatar = '🙂';
  @override void dispose() { for (final c in [_account, _password, _name, _phone, _group, _address]) { c.dispose(); } super.dispose(); }
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openMemberSignup() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final phone = TextEditingController();
    final company = TextEditingController();
    bool loading = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('일반 회원가입'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: '이름')),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: '이메일')),
                  TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: '암호')),
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '전화번호')),
                  TextField(controller: company, decoration: const InputDecoration(labelText: '회사명(선택)')),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('일반 회원은 관리자 승인 없이 가입할 수 있습니다.', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: loading ? null : () => Navigator.pop(dialogContext), child: const Text('취소')),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        if (name.text.trim().isEmpty || email.text.trim().isEmpty || password.text.isEmpty) {
                          _message('이름, 이메일, 암호를 입력해 주세요.');
                          return;
                        }
                        setDialogState(() => loading = true);
                        try {
                          // 일반 회원은 member + approved로 생성합니다. 관리자/파트너 계정은 별도 발급 절차를 사용합니다.
                          final result = await AuthService.instance.signUp(
                            email: email.text.trim(),
                            password: password.text,
                            name: name.text.trim(),
                            phone: phone.text.trim(),
                            company: company.text.trim(),
                            role: UserRole.member,
                            verificationMethod: 'email',
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (result.emailConfirmationRequired) {
                            _message('회원가입이 완료되었습니다. 이메일 인증 후 접속해 주세요.');
                          } else {
                            _message('회원가입이 완료되었습니다. 바로 접속할 수 있습니다.');
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(() => loading = false);
                            _message('회원가입 실패: $error');
                          }
                        }
                      },
                child: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('가입하기'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      email.dispose();
      password.dispose();
      phone.dispose();
      company.dispose();
    }
  }

  Future<void> _login() async {
    if (_account.text.trim().isEmpty || _password.text.isEmpty) { _message('계정과 암호를 입력해 주세요.'); return; }
    try {
      final user = await AuthService.instance.signIn(email: _account.text.trim(), password: _password.text);
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
          _rolePicker(),
          const SizedBox(height: 18),
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
                onPressed: () {
                  setState(() {
                    _obscure = !_obscure;
                  });
                },
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          _check(
            '회원아이디 기억하기',
            _rememberAccount,
                (value) {
              setState(() {
                _rememberAccount = value;
              });
            },
          ),
          _check(
            '암호 기억하기',
            _rememberPassword,
                (value) {
              setState(() {
                _rememberPassword = value;
              });
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _login,
            child: const Text('접속'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _openMemberSignup,
            child: const Text('회원가입'),
          ),
        ],
      ],
    );
  }

  Widget _rolePicker() => SegmentedButton<UserRole>(segments: const [ButtonSegment(value: UserRole.member, label: Text('일반 회원')), ButtonSegment(value: UserRole.admin, label: Text('관리자')), ButtonSegment(value: UserRole.partner, label: Text('협력/파트너사'))], selected: {_role}, onSelectionChanged: (v) => setState(() => _role = v.first));
  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(value: value, onChanged: (v) => onChanged(v ?? false), title: Text(label), contentPadding: EdgeInsets.zero, dense: true);
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
              icon: const Icon(Icons.camera_alt, color: AppColors.primary),
              onSelected: (v) {
                if (v == 'camera') _message('카메라 연결 위치입니다.');
                if (v == 'photo') _message('사진 선택 연결 위치입니다.');
                if (v == 'character') setState(() => _avatar = '🐼');
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'camera', child: Text('카메라')),
                PopupMenuItem(value: 'photo', child: Text('사진 선택')),
                PopupMenuItem(value: 'character', child: Text('귀여운 캐릭터 선택')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(user.name.isEmpty ? '회원' : user.name,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: AppColors.primary)),
        const SizedBox(height: 8),
        Chip(label: Text(user.role == UserRole.admin ? '관리자' : user.role == UserRole.partner ? '협력/파트너사' : '일반 회원')),
        const SizedBox(height: 12),
        Card(child: Column(children: [
          _info('전화번호', user.phone),
          _info('그룹', user.role == UserRole.admin ? '관리자' : user.role == UserRole.partner ? '협력/파트너사' : '일반 고객'),
          _info('주소', user.address),
        ])),
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
  Widget _info(String label, String value) => ListTile(title: Text(label, style: const TextStyle(color: AppColors.textSecondary)), subtitle: Text(value.isEmpty ? '등록되지 않음' : value));
}

