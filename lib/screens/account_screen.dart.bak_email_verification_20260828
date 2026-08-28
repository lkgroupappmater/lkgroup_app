import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../utils/form_validators.dart';

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
    this.onUserUpdated,
  });

  final AppUser? currentUser;
  final ValueChanged<AppUser>? onLoggedIn;
  final VoidCallback? onLoggedOut;
  final ValueChanged<AppUser>? onUserUpdated;

  @override
  State<AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<AccountBody> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _rememberAccount = false;
  bool _rememberPassword = false;
  AppUser? _displayUser;

  @override
  void initState() {
    super.initState();
    _displayUser = widget.currentUser;
  }

  @override
  void didUpdateWidget(covariant AccountBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser?.id != widget.currentUser?.id ||
        oldWidget.currentUser?.role != widget.currentUser?.role) {
      _displayUser = widget.currentUser;
    }
  }

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
    final result = await showDialog<_SignupData>(
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
      );
      if (!mounted) return;
      if (result.role == UserRole.member) {
        _message(authResult.emailConfirmationRequired
            ? '회원가입이 완료되었습니다. 이메일 인증 후 접속해 주세요.'
            : '회원가입이 완료되었습니다. 바로 접속할 수 있습니다.');
      } else {
        _message('${result.role.label} 가입 신청이 완료되었습니다. 총괄 관리자 승인 후 접속할 수 있습니다.');
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

  Future<void> _openProfileEdit() async {
    final user = _displayUser;
    if (user == null) return;
    final result = await showDialog<_ProfileEditData>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProfileEditDialog(user: user),
    );
    if (result == null) return;
    try {
      final updated = await AuthService.instance.updateProfile(
        name: result.name,
        phone: result.phone,
        company: result.company,
        address: result.address,
      );
      if (!mounted) return;
      setState(() => _displayUser = updated);
      widget.onUserUpdated?.call(updated);
      _message('회원 정보를 변경했습니다.');
    } catch (e) {
      _message('회원 정보 변경 실패: $e');
    }
  }

  Future<void> _openPasswordChange() async {
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PasswordDialog(),
    );
    if (password == null) return;
    try {
      await AuthService.instance.updatePassword(password);
      _message('암호를 변경했습니다.');
    } catch (e) {
      _message('암호 변경 실패: $e');
    }
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (file == null) return;
      final updated = await AuthService.instance.uploadAvatar(file);
      if (!mounted) return;
      setState(() => _displayUser = updated);
      widget.onUserUpdated?.call(updated);
      _message('프로필 사진을 변경했습니다.');
    } catch (e) {
      _message('프로필 사진 변경 실패: $e');
    }
  }

  String _fallbackAvatar(AppUser user) {
    const avatars = ['🐼', '🐻', '🐰', '🐯', '🦊', '🐨', '🐶', '🐱'];
    final seed = user.id.codeUnits.fold<int>(0, (a, b) => a + b);
    return avatars[seed % avatars.length];
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_displayUser != null) ...[
            _profile(_displayUser!),
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
                hintText: '예: member@example.com',
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
                hintText: '대문자 + 소문자 + 숫자 포함 8자 이상',
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
            CheckboxListTile(
              value: _rememberAccount,
              onChanged: (v) =>
                  setState(() => _rememberAccount = v ?? false),
              title: const Text('회원아이디 기억하기'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              value: _rememberPassword,
              onChanged: (v) =>
                  setState(() => _rememberPassword = v ?? false),
              title: const Text('암호 기억하기'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _login, child: const Text('접속')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _openSignup,
              child: const Text('회원가입'),
            ),
          ],
        ],
      );

  Widget _profile(AppUser user) {
    final hasAvatar =
        user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty;
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.inputFill,
              backgroundImage:
                  hasAvatar ? NetworkImage(user.avatarUrl!) : null,
              child: hasAvatar
                  ? null
                  : Text(_fallbackAvatar(user),
                      style: const TextStyle(fontSize: 42)),
            ),
            PopupMenuButton<ImageSource>(
              icon: const Icon(Icons.camera_alt, color: AppColors.primary),
              onSelected: _pickAvatar,
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: ImageSource.camera, child: Text('카메라')),
                PopupMenuItem(
                    value: ImageSource.gallery, child: Text('사진 선택')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          user.name.isEmpty ? user.email : user.name,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Chip(label: Text(user.role.label)),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _info('전화번호', user.phone),
              _info('권한', user.role.label),
              _info('회사명', user.company),
              _info('주소', user.address),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _openProfileEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('회원 정보 변경'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openPasswordChange,
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
        title: Text(label,
            style: const TextStyle(color: AppColors.textSecondary)),
        subtitle: Text(value.isEmpty ? '등록되지 않음' : value),
      );
}

class _SignupDialog extends StatefulWidget {
  const _SignupDialog();

  @override
  State<_SignupDialog> createState() => _SignupDialogState();
}

class _SignupDialogState extends State<_SignupDialog> {
  final _formKey = GlobalKey<FormState>();
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

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('회원 가입'),
        content: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: '이름', hintText: '예: 홍길동'),
                  validator: (v) => FormValidators.requiredText(v, '이름'),
                ),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: '이메일',
                      hintText: '예: member@example.com'),
                  validator: FormValidators.email,
                ),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '암호',
                    hintText: '예: Lkgroup2026',
                    helperText: '대문자·소문자·숫자를 각각 1자 이상 포함, 8자 이상',
                  ),
                  validator: FormValidators.password,
                ),
                TextFormField(
                  controller: _passwordConfirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '암호확인',
                      hintText: '위 암호를 다시 입력'),
                  validator: (v) {
                    if ((v ?? '') != _password.text) {
                      return '암호가 서로 일치하지 않습니다.';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '전화번호',
                    hintText: '예: 020-5889-2547',
                    helperText: '02058892547로 입력해도 저장 시 자동으로 형식을 맞춥니다.',
                  ),
                  validator: FormValidators.phone,
                ),
                TextFormField(
                  controller: _company,
                  decoration: const InputDecoration(
                      labelText: '회사명(선택)',
                      hintText: '예: LK Trading'),
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
                        value: UserRole.member, label: Text('일반회원')),
                    ButtonSegment(
                        value: UserRole.admin, label: Text('관리자')),
                    ButtonSegment(
                        value: UserRole.partner,
                        label: Text('협력/파트너사')),
                  ],
                  selected: {_role},
                  onSelectionChanged: (v) =>
                      setState(() => _role = v.first),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _SignupData(
                  name: _name.text.trim(),
                  email: _email.text.trim(),
                  password: _password.text,
                  phone: FormValidators.normalizePhone(_phone.text),
                  company: _company.text.trim(),
                  role: _role,
                ),
              );
            },
            child: const Text('가입하기'),
          ),
        ],
      );
}

class _SignupData {
  const _SignupData({
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
    required this.company,
    required this.role,
  });
  final String name, email, password, phone, company;
  final UserRole role;
}

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.user});
  final AppUser user;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _company;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.name);
    _phone = TextEditingController(text: widget.user.phone);
    _company = TextEditingController(text: widget.user.company);
    _address = TextEditingController(text: widget.user.address);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _company.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('회원 정보 변경'),
        content: Form(
          key: _key,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: '이름', hintText: '예: 홍길동'),
                  validator: (v) => FormValidators.requiredText(v, '이름'),
                ),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                      labelText: '전화번호',
                      hintText: '예: 020-5889-2547'),
                  validator: FormValidators.phone,
                ),
                TextFormField(
                  controller: _company,
                  decoration: const InputDecoration(
                      labelText: '회사명(선택)',
                      hintText: '예: LK Trading'),
                ),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(
                      labelText: '주소(선택)',
                      hintText: '예: Vientiane, Laos'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          FilledButton(
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              Navigator.pop(
                context,
                _ProfileEditData(
                  name: _name.text.trim(),
                  phone: FormValidators.normalizePhone(_phone.text),
                  company: _company.text.trim(),
                  address: _address.text.trim(),
                ),
              );
            },
            child: const Text('저장'),
          ),
        ],
      );
}

class _ProfileEditData {
  const _ProfileEditData({
    required this.name,
    required this.phone,
    required this.company,
    required this.address,
  });
  final String name, phone, company, address;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _key = GlobalKey<FormState>();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('암호 변경'),
        content: Form(
          key: _key,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _p1,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '새 암호',
                  hintText: '예: Lkgroup2026',
                  helperText: '대문자·소문자·숫자 포함 8자 이상',
                ),
                validator: FormValidators.password,
              ),
              TextFormField(
                controller: _p2,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: '새 암호 확인'),
                validator: (v) =>
                    v == _p1.text ? null : '암호가 서로 일치하지 않습니다.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          FilledButton(
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              Navigator.pop(context, _p1.text);
            },
            child: const Text('변경'),
          ),
        ],
      );
}
