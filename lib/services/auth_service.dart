// lib/services/auth_service.dart

import '../models/app_user.dart';

// ---------------------------------------------------------------------------
// AuthException
// ---------------------------------------------------------------------------

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}

// ---------------------------------------------------------------------------
// Mock credentials
// ---------------------------------------------------------------------------

class _MockAccount {
  const _MockAccount({
    required this.email,
    required this.password,
    required this.id,
    required this.name,
    required this.role,
    this.phone,
    this.company,
  });

  final String email;
  final String password;
  final String id;
  final String name;
  final UserRole role;
  final String? phone;
  final String? company;
}

const List<_MockAccount> _mockAccounts = [
  _MockAccount(
    email: 'admin@cargoflow.dev',
    password: 'admin1234',
    id: 'mock-admin-001',
    name: '관리자',
    role: UserRole.admin,
    phone: '010-0000-0001',
    company: 'CargoFlow',
  ),
  _MockAccount(
    email: 'partner@example.com',
    password: 'partner1234',
    id: 'mock-partner-001',
    name: '파트너',
    role: UserRole.partner,
    phone: '010-0000-0002',
    company: 'Example Co.',
  ),
  _MockAccount(
    email: 'member@cargoflow.dev',
    password: 'member1234',
    id: 'mock-member-001',
    name: '회원',
    role: UserRole.member,
    phone: '010-0000-0003',
  ),
];

// ---------------------------------------------------------------------------
// AuthService singleton
// ---------------------------------------------------------------------------

class AuthService {
  AuthService._internal();

  static final AuthService instance = AuthService._internal();

  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;

  bool get isAuthenticated =>
      _currentUser != null && _currentUser!.role != UserRole.guest;

  // -------------------------------------------------------------------------
  // restoreSession
  // -------------------------------------------------------------------------

  Future<void> restoreSession() async {
    // TODO(supabase): restore session from Supabase / secure storage
    // e.g. final session = await Supabase.instance.client.auth.currentSession;
    // if (session != null) { ... }
    _currentUser = null;
  }

  // -------------------------------------------------------------------------
  // signIn
  // -------------------------------------------------------------------------

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    // TODO(supabase): replace mock with real Supabase sign-in
    // final response = await Supabase.instance.client.auth
    //     .signInWithPassword(email: email, password: password);
    // if (response.user == null) throw AuthException('로그인에 실패했습니다.');

    await Future.delayed(const Duration(milliseconds: 300)); // simulate latency

    final trimmedEmail = email.trim().toLowerCase();
    final match = _mockAccounts.where(
          (a) => a.email == trimmedEmail && a.password == password,
    );

    if (match.isEmpty) {
      throw AuthException('계정 또는 암호가 올바르지 않습니다.');
    }

    final account = match.first;
    final user = AppUser(
      id: account.id,
      name: account.name,
      email: account.email,
      role: account.role,
      phone: account.phone,
      company: account.company,
    );

    _currentUser = user;
    return user;
  }

  // -------------------------------------------------------------------------
  // signOut
  // -------------------------------------------------------------------------

  Future<void> signOut() async {
    // TODO(supabase): await Supabase.instance.client.auth.signOut();
    _currentUser = null;
  }

  // -------------------------------------------------------------------------
  // continueAsGuest
  // -------------------------------------------------------------------------

  void continueAsGuest() {
    // TODO(supabase): no server call needed; clears any existing session locally
    _currentUser = AppUser(
      id: 'guest',
      name: '비회원',
      email: '',
      role: UserRole.guest,
    );
  }
}
