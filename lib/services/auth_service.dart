import '../config/supabase_config.dart';
import '../models/app_user.dart';
import 'supabase_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  bool get isAuthenticated => SupabaseService.isReady
      ? SupabaseService.client.auth.currentUser != null
      : _currentUser != null && _currentUser!.role != UserRole.guest;

  Future<void> restoreSession() async {
    if (!SupabaseConfig.isConfigured) return;
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    try {
      _currentUser =
          await _loadProfile(user.id, fallbackEmail: user.email ?? '');
    } catch (_) {
      // 승인대기/권한오류 세션이 앱 시작을 중단시키지 않도록 로그아웃 상태로 복구합니다.
      await SupabaseService.client.auth.signOut();
      _currentUser = null;
    }
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthException('Supabase 설정 후 로그인할 수 있습니다.');
    }

    final response = await SupabaseService.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) throw const AuthException('로그인에 실패했습니다.');

    try {
      _currentUser =
          await _loadProfile(user.id, fallbackEmail: user.email ?? email);
      return _currentUser!;
    } catch (e) {
      await SupabaseService.client.auth.signOut();
      rethrow;
    }
  }

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String name,
    String phone = '',
    String company = '',
    UserRole role = UserRole.member,
    String verificationMethod = 'email',
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthException('Supabase 설정 후 회원가입할 수 있습니다.');
    }
    if (role != UserRole.member &&
        role != UserRole.partner &&
        role != UserRole.admin) {
      throw const AuthException('가입 신청 가능한 권한이 아닙니다.');
    }

    final response = await SupabaseService.client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': name.trim(),
        'phone': phone.trim(),
        'company': company.trim(),
        'requested_role': role.name,
        'role': role.name,
        'verification_method': verificationMethod,
      },
    );

    final user = response.user;
    if (user == null) throw const AuthException('회원가입에 실패했습니다.');

    final pending = role != UserRole.member;

    // 관리자/파트너 가입 신청이 signUp 직후 세션을 발급받더라도
    // 승인 전에는 로그인 상태로 남기지 않습니다.
    if (pending && response.session != null) {
      await SupabaseService.client.auth.signOut();
    }

    final resultUser = AppUser(
      id: user.id,
      email: user.email ?? email.trim(),
      name: name.trim(),
      phone: phone.trim(),
      company: company.trim(),
      role: pending ? UserRole.member : UserRole.member,
    );

    return AuthResult(
      user: resultUser,
      emailConfirmationRequired: response.session == null,
    );
  }

  Future<void> signOut() async {
    if (SupabaseConfig.isConfigured) {
      await SupabaseService.client.auth.signOut();
    }
    _currentUser = null;
  }

  void continueAsGuest() {
    _currentUser =
        const AppUser(id: 'guest', name: '비회원', role: UserRole.guest);
  }

  Future<AppUser> _loadProfile(
    String id, {
    required String fallbackEmail,
  }) async {
    final row = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (row == null) {
      throw const AuthException('회원 프로필을 찾을 수 없습니다.');
    }

    final approval = row['approval_status']?.toString() ?? 'approved';
    if (approval != 'approved') {
      throw AuthException(
        approval == 'pending'
            ? '총괄 관리자 승인 대기 중인 계정입니다.'
            : '승인되지 않은 계정입니다.',
      );
    }

    return AppUser.fromMap({
      'id': id,
      'email': fallbackEmail,
      ...row,
    });
  }

  Future<void> requestStaffOrPartnerAccount(
    AccountProvisionRequest request,
  ) async {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthException('Supabase 설정이 필요합니다.');
    }
    if (request.role != UserRole.staff &&
        request.role != UserRole.partner) {
      throw const AuthException(
          '계정 발급 요청은 직원 또는 협력·파트너사만 가능합니다.');
    }
    await SupabaseService.client
        .from('account_provision_requests')
        .insert(request.toMap());
  }

  static List<MockAccountInfo> get demoAccounts =>
      const <MockAccountInfo>[];
}
