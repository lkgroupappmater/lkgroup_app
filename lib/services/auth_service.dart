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
    _currentUser = await _loadProfile(user.id, fallbackEmail: user.email ?? '');
  }

  Future<AppUser> signIn({required String email, required String password}) async {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthException('Supabase 설정 후 로그인할 수 있습니다.');
    }
    final response = await SupabaseService.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) throw const AuthException('로그인에 실패했습니다.');
    _currentUser = await _loadProfile(user.id, fallbackEmail: user.email ?? email);
    return _currentUser!;
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
    final response = await SupabaseService.client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': name,
        'phone': phone,
        'company': company,
        'role': role.name,
        // 추후 phone/SMS/OAuth 등을 추가할 때 이 값만 확장합니다.
        'verification_method': verificationMethod,
      },
    );
    final user = response.user;
    if (user == null) throw const AuthException('회원가입에 실패했습니다.');

    // 일반 회원은 가입 즉시 사용할 수 있도록 승인 상태를 approved로 저장합니다.
    // profiles 테이블에 가입 트리거가 있다면 upsert가 기존 행도 안전하게 갱신합니다.
    if (role == UserRole.member) {
      await SupabaseService.client.from('profiles').upsert({
        'id': user.id,
        'email': user.email ?? email.trim(),
        'name': name.trim(),
        'phone': phone.trim(),
        'company': company.trim(),
        'role': UserRole.member.name,
        'approval_status': 'approved',
      });
    }
    final profile = await _loadProfile(user.id, fallbackEmail: user.email ?? email);
    _currentUser = profile;
    return AuthResult(
      user: profile,
      emailConfirmationRequired: response.session == null,
    );
  }

  Future<void> signOut() async {
    if (SupabaseConfig.isConfigured) await SupabaseService.client.auth.signOut();
    _currentUser = null;
  }

  void continueAsGuest() {
    _currentUser = const AppUser(id: 'guest', name: '비회원', role: UserRole.guest);
  }

  Future<AppUser> _loadProfile(String id, {required String fallbackEmail}) async {
    final row = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    final approval = row?['approval_status']?.toString() ?? 'approved';
    if (approval != 'approved') {
      throw AuthException(approval == 'pending' ? '관리자 승인 대기 중인 계정입니다.' : '승인되지 않은 계정입니다.');
    }
    return AppUser.fromMap({
      'id': id,
      'email': fallbackEmail,
      ...?row,
    });
  }

  Future<void> requestStaffOrPartnerAccount(AccountProvisionRequest request) async {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthException('Supabase 설정이 필요합니다.');
    }
    if (request.role != UserRole.staff && request.role != UserRole.partner) {
      throw const AuthException('계정 발급 요청은 직원 또는 협력·파트너사만 가능합니다.');
    }
    await SupabaseService.client
        .from('account_provision_requests')
        .insert(request.toMap());
  }

  static List<MockAccountInfo> get demoAccounts => const <MockAccountInfo>[];
}

