$ErrorActionPreference = "Stop"

$path = "lib/screens/account_screen.dart"
if (-not (Test-Path $path)) {
    throw "File not found: $path"
}

$resolved = (Resolve-Path $path).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)
$text = [System.IO.File]::ReadAllText($resolved, $utf8)

if ($text.Contains("// LK_EMAIL_VERIFICATION_V1")) {
    Write-Host "[SKIP] account_screen.dart email verification patch already applied."
    exit 0
}

$backup = "$resolved.bak_email_verification_20260828"
if (-not (Test-Path $backup)) {
    [System.IO.File]::Copy($resolved, $backup)
    Write-Host "[OK] Backup created: $backup"
}

function Replace-Range(
    [string]$Source,
    [string]$StartMarker,
    [string]$EndMarker,
    [string]$Replacement
) {
    $start = $Source.IndexOf($StartMarker)
    if ($start -lt 0) {
        throw "Start marker not found: $StartMarker"
    }

    $end = $Source.IndexOf($EndMarker, $start)
    if ($end -lt 0) {
        throw "End marker not found: $EndMarker"
    }

    return $Source.Substring(0, $start) +
        $Replacement +
        $Source.Substring($end)
}

# 1) signup launcher
$signupLauncher = @'
  // LK_EMAIL_VERIFICATION_V1
  Future<void> _openSignup() async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SignupDialog(),
    );
    if (message != null && mounted) {
      _message(message);
    }
  }

'@

$text = Replace-Range `
    $text `
    "  Future<void> _openSignup() async {" `
    "  Future<void> _login() async {" `
    $signupLauncher

# 2) password-change launcher
$passwordLauncher = @'
  Future<void> _openPasswordChange() async {
    final user = _displayUser;
    if (user == null) return;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordDialog(email: user.email),
    );

    if (changed == true && mounted) {
      _message('암호를 변경했습니다. 이메일 본인 인증도 완료되었습니다.');
    }
  }

'@

$text = Replace-Range `
    $text `
    "  Future<void> _openPasswordChange() async {" `
    "  Future<void> _pickAvatar(ImageSource source) async {" `
    $passwordLauncher

# 3) signup dialog block
$signupDialog = @'
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
  final _emailCode = TextEditingController();

  UserRole _role = UserRole.member;
  bool _codeSent = false;
  bool _busy = false;
  String? _serverError;

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
          _serverError =
              'Supabase의 Confirm Email 설정이 꺼져 있습니다. '
              '이메일 인증 코드 회원가입을 사용하려면 Confirm Email을 활성화해 주세요.';
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
      setState(() => _serverError = '인증 코드 전송 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _busy = true;
      _serverError = null;
    });

    try {
      await AuthService.instance.resendSignupEmailCode(_email.text.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = '인증 코드 재전송 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_emailCode.text.trim().isEmpty) {
      setState(() => _serverError = '이메일 인증 코드를 입력해 주세요.');
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
          ? '이메일 인증 및 회원가입이 완료되었습니다. 로그인해 주세요.'
          : '이메일 인증 및 ${_role.label} 가입 신청이 완료되었습니다. '
              '총괄 관리자 승인 후 로그인할 수 있습니다.';
      Navigator.pop(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = '이메일 인증 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  readOnly: _codeSent,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    hintText: '예: 홍길동',
                  ),
                  validator: (v) => FormValidators.requiredText(v, '이름'),
                ),
                TextFormField(
                  controller: _email,
                  readOnly: _codeSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: '이메일',
                    hintText: '예: member@example.com',
                  ),
                  validator: FormValidators.email,
                ),
                TextFormField(
                  controller: _password,
                  readOnly: _codeSent,
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
                  readOnly: _codeSent,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '암호확인',
                    hintText: '위 암호를 다시 입력',
                  ),
                  validator: (v) {
                    if ((v ?? '') != _password.text) {
                      return '암호가 서로 일치하지 않습니다.';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _phone,
                  readOnly: _codeSent,
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
                  readOnly: _codeSent,
                  decoration: const InputDecoration(
                    labelText: '회사명(선택)',
                    hintText: '예: LK Trading',
                  ),
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
                      label: const Text('이메일 인증 코드 보내기'),
                    ),
                  ),
                if (_codeSent) ...[
                  TextFormField(
                    controller: _emailCode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: '이메일 인증 코드',
                      hintText: '메일로 받은 인증 코드 입력',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _resendCode,
                      child: const Text('인증 코드 다시 보내기'),
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
                      color: AppColors.error,
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
            child: const Text('취소'),
          ),
          if (_codeSent)
            FilledButton(
              onPressed: _busy ? null : _verifyCode,
              child: const Text('인증 확인'),
            ),
        ],
      );
}

'@

$text = Replace-Range `
    $text `
    "class _SignupDialog extends StatefulWidget {" `
    "class _ProfileEditDialog extends StatefulWidget {" `
    $signupDialog

# 4) password dialog is currently the final class in account_screen.dart.
$passwordDialog = @'
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.email});

  final String email;

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
      setState(() => _codeSent = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = '이메일 인증 코드 전송 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_key.currentState!.validate()) return;
    if (!_codeSent || _emailCode.text.trim().isEmpty) {
      setState(() => _serverError = '이메일 인증 코드를 먼저 받아 입력해 주세요.');
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
      setState(() => _serverError = '암호 변경 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('암호 변경'),
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
                  decoration: const InputDecoration(
                    labelText: '기존 암호',
                    hintText: '현재 사용 중인 암호 입력',
                  ),
                  validator: (v) => FormValidators.requiredText(v, '기존 암호'),
                ),
                TextFormField(
                  controller: _newPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '새 암호',
                    hintText: '예: Lkgroup2026',
                    helperText: '대문자·소문자·숫자 포함 8자 이상',
                  ),
                  validator: FormValidators.password,
                ),
                TextFormField(
                  controller: _newPasswordConfirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '새 암호 확인',
                  ),
                  validator: (v) => v == _newPassword.text
                      ? null
                      : '새 암호가 서로 일치하지 않습니다.',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '인증 이메일: ${widget.email}',
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
                      _codeSent
                          ? '이메일 인증 코드 다시 보내기'
                          : '이메일 인증 코드 보내기',
                    ),
                  ),
                ),
                if (_codeSent) ...[
                  TextFormField(
                    controller: _emailCode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: '이메일 인증 코드',
                      hintText: '메일로 받은 인증 코드 입력',
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? '이메일 인증 코드를 입력해 주세요.'
                        : null,
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
                      color: AppColors.error,
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
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _busy ? null : _changePassword,
            child: const Text('변경'),
          ),
        ],
      );
}
'@

$pwdStart = $text.IndexOf("class _PasswordDialog extends StatefulWidget {")
if ($pwdStart -lt 0) {
    throw "Password dialog marker not found."
}
$text = $text.Substring(0, $pwdStart) + $passwordDialog

[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "[OK] account_screen.dart patched."
Write-Host "[OK] Only signup/password verification UI blocks were changed."
