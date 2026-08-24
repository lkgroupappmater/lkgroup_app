// lib/services/auth_service.dart
//
// ─── 실서버 연동 시 교체 가이드 ────────────────────────────────────────────
//  [SUPABASE] 태그가 붙은 주석 블록을 Supabase Auth 호출로 교체하세요.
//  [REST]     태그는 일반 JWT REST API 연동 지점입니다.
//  [STORAGE]  태그는 세션 영속화(shared_preferences / flutter_secure_storage)
//             연동 지점입니다.
// ──────────────────────────────────────────────────────────────────────────

import '../data/mock_data.dart';
import '../models/app_user.dart';

// ── Mock 계정 데이터 ────────────────────────────────────────────────────────
// [SUPABASE] 이 맵 전체를 제거하고 Supabase.instance.client.auth.signInWithPassword() 를 사용하세요.
// [REST]     POST /auth/login { email, password } → { token, user } 로 교체하세요.
const _mockAccounts = <String, Map<String, dynamic>>{
  'admin@cargoflow.dev': {
    'password': 'admin1234',
    'user': {
      'id': 'u-001',
      'name': '관리자',
      'email': 'admin@cargoflow.dev',
      'role': UserRole.admin,
      'company': 'CargoFlow 본사',
      'avatarUrl': null,
    },
  },
  'partner@example.com': {
    'password': 'partner1234',
    'user': {
      'id': 'u-002',
      'name': '홍길동 (거래처)',
      'email': 'partner@example.com',
      'role': UserRole.partner,
      'company': '(주)글로벌 물류',
      'avatarUrl': null,
    },
  },
  'member@cargoflow.dev': {
    'password': 'member1234',
    'user': {
      'id': 'u-003',
      'name': '김직원',
      'email': 'member@cargoflow.dev',
      'role': UserRole.member,
      'company': 'CargoFlow 본사',
      'avatarUrl': null,
    },
  },
};

// ── 게스트 싱글턴 ────────────────────────────────────────────────────────────
const _guestUser = AppUser(
  id: 'guest',
  name: '게스트',
  email: '',
  role: UserRole.guest,
  company: null,
  avatarUrl: null,
);

// ── AuthService ──────────────────────────────────────────────────────────────
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // ── 인메모리 세션 ───────────────────────────────────────────────────────
  // [STORAGE] 아래 필드를 SharedPreferences / flutter_secure_storage 로 교체하세요.
  //   - 로그인 성공 시 토큰·userId 를 secure storage 에 write
  //   - 앱 시작 시 restoreSession() 에서 read → 서버 검증
  AppUser _currentUser = _guestUser;

  /// 현재 로그인 사용자 (미로그인 → guest)
  AppUser get currentUser => _currentUser;

  /// 로그인 여부
  bool get isAuthenticated => _currentUser.role != UserRole.guest;

  // ── 로그인 ───────────────────────────────────────────────────────────────
  /// 성공 시 [AppUser] 반환, 실패 시 [AuthException] throw
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    // ── 네트워크 지연 시뮬레이션 ──────────────────────────────────────────
    await Future.delayed(const Duration(milliseconds: 900));

    // ── [SUPABASE] 교체 지점 ─────────────────────────────────────────────
    // final response = await Supabase.instance.client.auth.signInWithPassword(
    //   email: email,
    //   password: password,
    // );
    // if (response.user == null) throw AuthException('로그인에 실패했습니다.');
    // final supaUser = response.user!;
    // // profiles 테이블에서 role 등 추가 정보 조회
    // final profile = await Supabase.instance.client
    //     .from('profiles')
    //     .select()
    //     .eq('id', supaUser.id)
    //     .single();
    // _currentUser = AppUser.fromMap(profile);
    // return _currentUser;

    // ── [REST] 교체 지점 ──────────────────────────────────────────────────
    // final res = await http.post(
    //   Uri.parse('$baseUrl/auth/login'),
    //   body: jsonEncode({'email': email, 'password': password}),
    //   headers: {'Content-Type': 'application/json'},
    // );
    // if (res.statusCode != 200) throw AuthException('로그인에 실패했습니다.');
    // final data = jsonDecode(res.body);
    // // [STORAGE] JWT 토큰 저장:
    // // await secureStorage.write(key: 'jwt', value: data['token']);
    // _currentUser = AppUser.fromMap(data['user']);
    // return _currentUser;

    // ── Mock 검증 ─────────────────────────────────────────────────────────
    final trimmedEmail = email.trim().toLowerCase();
    final account = _mockAccounts[trimmedEmail];

    if (account == null) {
      throw const AuthException('등록되지 않은 이메일입니다.');
    }
    if (account['password'] != password) {
      throw const AuthException('비밀번호가 올바르지 않습니다.');
    }

    final userMap = account['user'] as Map<String, dynamic>;
    _currentUser = AppUser(
      id: userMap['id'] as String,
      name: userMap['name'] as String,
      email: userMap['email'] as String,
      role: userMap['role'] as UserRole,
      company: userMap['company'] as String?,
      avatarUrl: userMap['avatarUrl'] as String?,
    );

    // [STORAGE] 세션 저장:
    // await _saveSession(_currentUser);

    return _currentUser;
  }

  // ── 로그아웃 ─────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    // [SUPABASE] await Supabase.instance.client.auth.signOut();
    // [REST]     POST /auth/logout (Authorization: Bearer $token)
    // [STORAGE]  await secureStorage.deleteAll();

    await Future.delayed(const Duration(milliseconds: 200));
    _currentUser = _guestUser;
  }

  // ── 세션 복원 (자동 로그인) ───────────────────────────────────────────────
  /// 앱 시작 시 호출. 저장된 세션이 있으면 복원한다.
  Future<AppUser> restoreSession() async {
    // [STORAGE] 세션 복원 지점:
    // final token = await secureStorage.read(key: 'jwt');
    // if (token == null) return _guestUser;
    //
    // [SUPABASE] Supabase SDK 는 자동으로 세션을 복원합니다:
    // final session = Supabase.instance.client.auth.currentSession;
    // if (session != null) {
    //   // 서버에서 최신 프로필 재조회
    //   final profile = await Supabase.instance.client
    //       .from('profiles').select().eq('id', session.user.id).single();
    //   _currentUser = AppUser.fromMap(profile);
    // }
    //
    // [REST] 토큰 유효성 검사:
    // final res = await http.get(Uri.parse('$baseUrl/auth/me'),
    //     headers: {'Authorization': 'Bearer $token'});
    // if (res.statusCode == 200) {
    //   _currentUser = AppUser.fromMap(jsonDecode(res.body));
    // } else {
    //   await secureStorage.deleteAll(); // 만료된 토큰 제거
    // }

    // 인메모리: 앱 재시작 시 항상 guest
    return _currentUser;
  }

  // ── 비로그인(게스트) 진행 ─────────────────────────────────────────────────
  void continueAsGuest() {
    _currentUser = _guestUser;
  }

  // ── Mock 계정 목록 (로그인 화면 데모 카드용) ─────────────────────────────
  static List<MockAccountInfo> get demoAccounts => [
    const MockAccountInfo(
      label: '관리자',
      email: 'admin@cargoflow.dev',
      password: 'admin1234',
      role: UserRole.admin,
    ),
    const MockAccountInfo(
      label: '거래처',
      email: 'partner@example.com',
      password: 'partner1234',
      role: UserRole.partner,
    ),
    const MockAccountInfo(
      label: '직원',
      email: 'member@cargoflow.dev',
      password: 'member1234',
      role: UserRole.member,
    ),
  ];

// ── 내부: 세션 저장 헬퍼 ─────────────────────────────────────────────────
// [STORAGE] 실제 저장 로직을 여기에 구현하세요.
// Future<void> _saveSession(AppUser user) async {
//   final prefs = await SharedPreferences.getInstance();
//   await prefs.setString('userId', user.id);
//   await prefs.setString('userEmail', user.email);
//   // 또는 flutter_secure_storage 사용:
//   // await secureStorage.write(key: 'jwt', value: token);
// }
}

// ── 예외 클래스 ──────────────────────────────────────────────────────────────
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ── 데모 계정 정보 모델 ───────────────────────────────────────────────────────
class MockAccountInfo {
  const MockAccountInfo({
    required this.label,
    required this.email,
    required this.password,
    required this.role,
  });

  final String label;
  final String email;
  final String password;
  final UserRole role;
}

