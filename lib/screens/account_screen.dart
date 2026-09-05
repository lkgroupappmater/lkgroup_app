import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/ui_localizations.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../utils/form_validators.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    this.currentUser,
    this.language = AppLanguage.korean,
  });

  final AppUser? currentUser;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: AccountBody(currentUser: currentUser, language: language),
        ),
      );
}

class AccountBody extends StatefulWidget {
  const AccountBody({
    super.key,
    this.currentUser,
    this.onLoggedIn,
    this.onLoggedOut,
    this.onUserUpdated,
    this.language = AppLanguage.korean,
  });

  final AppUser? currentUser;
  final ValueChanged<AppUser>? onLoggedIn;
  final VoidCallback? onLoggedOut;
  final ValueChanged<AppUser>? onUserUpdated;
  final AppLanguage language;

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

  String _t(String key) => AppStrings.get(widget.language, key);
  String _u(String korean) => UiLocalizations.get(widget.language, korean);
  String _ue(String prefix, Object error) =>
      UiLocalizations.error(widget.language, prefix, error);

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
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SignupDialog(language: widget.language),
    );
    if (message != null && mounted) {
      _message(message);
    }
  }

  Future<void> _login() async {
    if (_account.text.trim().isEmpty || _password.text.isEmpty) {
      _message(_u('계정과 암호를 입력해 주세요.'));
      return;
    }

    try {
      final user = await AuthService.instance.signIn(
        email: _account.text.trim(),
        password: _password.text,
      );
      if (mounted) widget.onLoggedIn?.call(user);
    } catch (error) {
      if (mounted) _message(_ue('접속 실패', error));
    }
  }

  Future<void> _openProfileEdit() async {
    final user = _displayUser;
    if (user == null) return;

    final result = await showDialog<_ProfileEditData>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProfileEditDialog(
        user: user,
        language: widget.language,
      ),
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
      _message(_u('회원 정보를 변경했습니다.'));
    } catch (e) {
      _message(_ue('회원 정보 변경 실패', e));
    }
  }

  Future<void> _openPasswordChange() async {
    final user = _displayUser;
    if (user == null) return;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordDialog(
        email: user.email,
        language: widget.language,
      ),
    );

    if (changed == true && mounted) {
      _message(_u('암호를 변경했습니다. 이메일 본인 인증도 완료되었습니다.'));
    }
  }

  Future<void> _openAccountDeletion() async {
    final user = _displayUser;
    if (user == null) return;

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountDeletionDialog(
        email: user.email,
        language: widget.language,
      ),
    );
    if (deleted == true && mounted) {
      setState(() => _displayUser = null);
      widget.onLoggedOut?.call();
      _message(_u('회원 탈퇴가 처리되었습니다.'));
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
      _message(_u('프로필 사진을 변경했습니다.'));
    } catch (e) {
      _message(_ue('프로필 사진 변경 실패', e));
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
              child: Text(_t('sign_out')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _openAccountDeletion,
              child: Text(_t('delete_account')),
            ),
          ] else ...[
            TextField(
              controller: _account,
              decoration: InputDecoration(
                labelText: _t('email_account'),
                hintText: _u('예: member@example.com'),
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: AppColors.inputFill,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: _t('password'),
                hintText: _u('대문자 + 소문자 + 숫자 포함 8자 이상'),
                prefixIcon: const Icon(Icons.lock_outline),
                filled: true,
                fillColor: AppColors.inputFill,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              value: _rememberAccount,
              onChanged: (v) =>
                  setState(() => _rememberAccount = v ?? false),
              title: Text(_t('remember_account')),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              value: _rememberPassword,
              onChanged: (v) =>
                  setState(() => _rememberPassword = v ?? false),
              title: Text(_t('remember_password')),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _login,
              child: Text(_t('sign_in')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _openSignup,
              child: Text(_t('sign_up')),
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
                  : Text(
                      _fallbackAvatar(user),
                      style: const TextStyle(fontSize: 42),
                    ),
            ),
            PopupMenuButton<ImageSource>(
              icon: const Icon(Icons.camera_alt, color: AppColors.primary),
              onSelected: _pickAvatar,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: ImageSource.camera,
                  child: Text(_t('camera')),
                ),
                PopupMenuItem(
                  value: ImageSource.gallery,
                  child: Text(_t('select_photo')),
                ),
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
        Chip(label: Text(user.role.localizedLabel(widget.language))),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _info(_t('phone'), user.phone),
              _info(_t('role'), user.role.localizedLabel(widget.language)),
              _info(_t('company'), user.company),
              _info(_t('address'), user.address),
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
                label: Text(_t('edit_profile')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openPasswordChange,
                icon: const Icon(Icons.lock_outline),
                label: Text(_t('change_password')),
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
        subtitle: Text(value.isEmpty ? _t('not_registered') : value),
      );
}

class _SignupDialog extends StatefulWidget {
  const _SignupDialog({required this.language});

  final AppLanguage language;

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
  final _emailCode = TextEditingController();

  UserRole _role = UserRole.member;
  bool _codeSent = false;
  bool _busy = false;
  String? _serverError;

  String _roleLabel(UserRole role) => role.localizedLabel(widget.language);
  String _u(String korean) => UiLocalizations.get(widget.language, korean);
  String _uf(String korean, Map<String, Object?> values) =>
      UiLocalizations.format(widget.language, korean, values);
  String _ue(String prefix, Object error) =>
      UiLocalizations.error(widget.language, prefix, error);
  String? _validation(String? value) => value == null ? null : _u(value);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _phone.dispose();
    _company.dispose();
    _emailCode.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _serverError = null;
    });

    try {
      final result = await AuthService.instance.signUp(
        email: _email.text.trim(),
        password: _password.text,
        name: _name.text.trim(),
        phone: FormValidators.normalizePhone(_phone.text),
        company: _company.text.trim(),
        role: _role,
      );

      if (!result.emailConfirmationRequired) {
        await AuthService.instance.signOut();
        if (!mounted) return;
        setState(() {
          _serverError = _u(
            'Supabase의 Confirm Email 설정이 꺼져 있습니다. 이메일 인증 코드 회원가입을 사용하려면 Confirm Email을 활성화해 주세요.',
          );
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _emailCode.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = _ue('인증 코드 전송 실패', e);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _busy = true;
      _serverError = null;
    });

    try {
      await AuthService.instance.resendSignupEmailCode(
        _email.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = _ue('인증 코드 재전송 실패', e);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    if (_emailCode.text.trim().isEmpty) {
      setState(() {
        _serverError = _u('이메일 인증 코드를 입력해 주세요.');
      });
      return;
    }

    setState(() {
      _busy = true;
      _serverError = null;
    });

    try {
      await AuthService.instance.verifySignupEmailCode(
        email: _email.text.trim(),
        code: _emailCode.text.trim(),
      );

      if (!mounted) return;

      final message = _role == UserRole.member
          ? _u('이메일 인증 및 회원가입이 완료되었습니다. 로그인해 주세요.')
          : _uf(
              '{role} 가입 신청이 완료되었습니다. 총괄 관리자 승인 후 로그인할 수 있습니다.',
              {'role': _roleLabel(_role)},
            );

      Navigator.pop(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = _ue('이메일 인증 실패', e);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_u('회원 가입')),
        content: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  readOnly: _codeSent,
                  decoration: InputDecoration(
                    labelText: _u('이름'),
                    hintText: _u('예: 홍길동'),
                  ),
                  validator: (v) => _validation(
                    FormValidators.requiredText(v, '이름'),
                  ),
                ),
                TextFormField(
                  controller: _email,
                  readOnly: _codeSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: _u('이메일'),
                    hintText: _u('예: member@example.com'),
                  ),
                  validator: (v) => _validation(FormValidators.email(v)),
                ),
                TextFormField(
                  controller: _password,
                  readOnly: _codeSent,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _u('암호'),
                    hintText: _u('예: Lkgroup2026'),
                    helperText: _u(
                      '대문자·소문자·숫자를 각각 1자 이상 포함, 8자 이상',
                    ),
                  ),
                  validator: (v) => _validation(FormValidators.password(v)),
                ),
                TextFormField(
                  controller: _passwordConfirm,
                  readOnly: _codeSent,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _u('암호확인'),
                    hintText: _u('위 암호를 다시 입력'),
                  ),
                  validator: (v) {
                    if ((v ?? '') != _password.text) {
                      return _u('암호가 서로 일치하지 않습니다.');
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _phone,
                  readOnly: _codeSent,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: _u('전화번호'),
                    hintText: '020-5889-2547',
                    helperText: _u(
                      '02058892547로 입력해도 저장 시 자동으로 형식을 맞춥니다.',
                    ),
                  ),
                  validator: (v) => _validation(FormValidators.phone(v)),
                ),
                TextFormField(
                  controller: _company,
                  readOnly: _codeSent,
                  decoration: InputDecoration(
                    labelText: _u('회사명(선택)'),
                    hintText: 'LK Trading',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _u('협력/파트너사 및 관리자는 총괄 관리자 승인이 필요 합니다.'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<UserRole>(
                  segments: [
                    ButtonSegment(
                      value: UserRole.member,
                      label: Text(_roleLabel(UserRole.member)),
                    ),
                    ButtonSegment(
                      value: UserRole.admin,
                      label: Text(_roleLabel(UserRole.admin)),
                    ),
                    ButtonSegment(
                      value: UserRole.partner,
                      label: Text(_roleLabel(UserRole.partner)),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged: _codeSent
                      ? null
                      : (v) => setState(() => _role = v.first),
                ),
                const SizedBox(height: 14),
                if (!_codeSent)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _sendCode,
                      icon: const Icon(Icons.email_outlined),
                      label: Text(_u('이메일 인증 코드 보내기')),
                    ),
                  ),
                if (_codeSent) ...[
                  TextFormField(
                    controller: _emailCode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: _u('이메일 인증 코드'),
                      hintText: _u('메일로 받은 인증 코드 입력'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _resendCode,
                      child: Text(_u('인증 코드 다시 보내기')),
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_serverError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _serverError!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(_u('취소')),
          ),
          if (_codeSent)
            FilledButton(
              onPressed: _busy ? null : _verifyCode,
              child: Text(_u('인증 확인 및 가입 완료')),
            ),
        ],
      );
}

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.user, required this.language});

  final AppUser user;
  final AppLanguage language;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _company;
  late final TextEditingController _address;

  String _u(String korean) => UiLocalizations.get(widget.language, korean);
  String? _validation(String? value) => value == null ? null : _u(value);

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
        title: Text(_u('회원 정보 변경')),
        content: Form(
          key: _key,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: _u('이름'),
                    hintText: _u('예: 홍길동'),
                  ),
                  validator: (v) => _validation(
                    FormValidators.requiredText(v, '이름'),
                  ),
                ),
                TextFormField(
                  controller: _phone,
                  decoration: InputDecoration(
                    labelText: _u('전화번호'),
                    hintText: '020-5889-2547',
                  ),
                  validator: (v) => _validation(FormValidators.phone(v)),
                ),
                TextFormField(
                  controller: _company,
                  decoration: InputDecoration(
                    labelText: _u('회사명(선택)'),
                    hintText: 'LK Trading',
                  ),
                ),
                TextFormField(
                  controller: _address,
                  decoration: InputDecoration(
                    labelText: _u('주소(선택)'),
                    hintText: 'Vientiane, Laos',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_u('취소')),
          ),
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
            child: Text(_u('저장')),
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

  final String name;
  final String phone;
  final String company;
  final String address;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.email, required this.language});

  final String email;
  final AppLanguage language;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _key = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _newPasswordConfirm = TextEditingController();
  final _emailCode = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _serverError;

  String _u(String korean) => UiLocalizations.get(widget.language, korean);
  String _uf(String korean, Map<String, Object?> values) =>
      UiLocalizations.format(widget.language, korean, values);
  String _ue(String prefix, Object error) =>
      UiLocalizations.error(widget.language, prefix, error);
  String? _validation(String? value) => value == null ? null : _u(value);

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _newPasswordConfirm.dispose();
    _emailCode.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _serverError = null;
    });

    try {
      await AuthService.instance.sendPasswordChangeVerificationCode();
      if (!mounted) return;
      setState(() {
        _codeSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = _ue('이메일 인증 코드 전송 실패', e);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changePassword() async {
    if (!_key.currentState!.validate()) return;

    if (!_codeSent || _emailCode.text.trim().isEmpty) {
      setState(() {
        _serverError = _u('이메일 인증 코드를 먼저 받아 입력해 주세요.');
      });
      return;
    }

    setState(() {
      _busy = true;
      _serverError = null;
    });

    try {
      await AuthService.instance.updatePasswordWithVerification(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
        verificationCode: _emailCode.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = _ue('암호 변경 실패', e);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_u('암호 변경')),
        content: Form(
          key: _key,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _currentPassword,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _u('기존 암호'),
                    hintText: _u('현재 사용 중인 암호 입력'),
                  ),
                  validator: (v) => _validation(
                    FormValidators.requiredText(v, '기존 암호'),
                  ),
                ),
                TextFormField(
                  controller: _newPassword,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _u('새 암호'),
                    hintText: _u('예: Lkgroup2026'),
                    helperText: _u('대문자·소문자·숫자 포함 8자 이상'),
                  ),
                  validator: (v) => _validation(FormValidators.password(v)),
                ),
                TextFormField(
                  controller: _newPasswordConfirm,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _u('새 암호 확인'),
                  ),
                  validator: (v) => v == _newPassword.text
                      ? null
                      : _u('새 암호가 서로 일치하지 않습니다.'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _uf('인증 이메일: {email}', {'email': widget.email}),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _sendCode,
                    icon: const Icon(Icons.email_outlined),
                    label: Text(
                      _u(_codeSent
                          ? '이메일 인증 코드 다시 보내기'
                          : '이메일 인증 코드 보내기'),
                    ),
                  ),
                ),
                if (_codeSent)
                  TextFormField(
                    controller: _emailCode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: _u('이메일 인증 코드'),
                      hintText: _u('메일로 받은 인증 코드 입력'),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? _u('이메일 인증 코드를 입력해 주세요.')
                        : null,
                  ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_serverError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _serverError!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                _busy ? null : () => Navigator.pop(context, false),
            child: Text(_u('취소')),
          ),
          FilledButton(
            onPressed: _busy ? null : _changePassword,
            child: Text(_u('변경')),
          ),
        ],
      );
}


class _AccountDeletionDialog extends StatefulWidget {
  const _AccountDeletionDialog({required this.email, required this.language});

  final String email;
  final AppLanguage language;

  @override
  State<_AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<_AccountDeletionDialog> {
  final _key = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _emailCode = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _serverError;

  String _u(String korean) => UiLocalizations.get(widget.language, korean);
  String _uf(String korean, Map<String, Object?> values) =>
      UiLocalizations.format(widget.language, korean, values);
  String _ue(String prefix, Object error) =>
      UiLocalizations.error(widget.language, prefix, error);
  String? _validation(String? value) => value == null ? null : _u(value);

  @override
  void dispose() {
    _currentPassword.dispose();
    _emailCode.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _serverError = null;
    });
    try {
      await AuthService.instance.sendAccountDeletionVerificationCode();
      if (!mounted) return;
      setState(() => _codeSent = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = _ue('이메일 인증 코드 전송 실패', e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!_key.currentState!.validate()) return;
    if (!_codeSent || _emailCode.text.trim().isEmpty) {
      setState(() =>
          _serverError = _u('이메일 인증 코드를 먼저 받아 입력해 주세요.'));
      return;
    }
    setState(() {
      _busy = true;
      _serverError = null;
    });
    try {
      await AuthService.instance.deleteMyAccount(
        currentPassword: _currentPassword.text,
        verificationCode: _emailCode.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = _ue('회원 탈퇴 실패', e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_u('회원 탈퇴')),
        content: Form(
          key: _key,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _u('회원 탈퇴를 진행하시겠습니까?'),
                ),
                const SizedBox(height: 8),
                Text(
                  _u('탈퇴 시 3일 동안 탈퇴 아이디/Email로 재가입이 안되니 신중하게 확인 바랍니다.'),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _currentPassword,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _u('본인 암호'),
                    hintText: _u('현재 사용 중인 암호 입력'),
                  ),
                  validator: (v) => _validation(
                    FormValidators.requiredText(v, '본인 암호'),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _uf('인증 이메일: {email}', {'email': widget.email}),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _sendCode,
                    icon: const Icon(Icons.email_outlined),
                    label: Text(
                      _u(_codeSent
                          ? '이메일 인증 코드 다시 보내기'
                          : '이메일 인증 코드 보내기'),
                    ),
                  ),
                ),
                if (_codeSent)
                  TextFormField(
                    controller: _emailCode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: _u('이메일 인증 코드'),
                      hintText: _u('메일로 받은 인증 코드 입력'),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? _u('이메일 인증 코드를 입력해 주세요.')
                        : null,
                  ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_serverError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _serverError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(_u('취소')),
          ),
          FilledButton(
            onPressed: _busy ? null : _delete,
            child: Text(_u('탈퇴 확인')),
          ),
        ],
      );
}
