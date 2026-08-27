// lib/services/auth_service.dart

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import '../config/supabase_config.dart';
import '../models/app_user.dart';

// Supabase가 설정되지 않은 개발 환경에서는 기존 데모 계정을 사용할 수 있습니다.
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
    email: 'staff@cargoflow.dev',
    password: 'staff1234',
    id: 'mock-staff-001',
    name: '직원',
    role: UserRole.staff,
    phone: '010-0000-0004',
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

class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  SupabaseClient? get _client => SupabaseConfig.isConfigured
      ? Supabase.instance.client
      : null;

  bool get isAuthenticated =>
      _currentUser != null && _currentUser!.role != UserRole.guest;

  Future<AppUser?> _loadProfile(User user) async {
    final client = _client;
    if (client == null) return null;
    final row = await client.from('profiles').select().eq('id', user.id).maybeSingle();
    if (row == null) return null;
    return AppUser.fromMap(<String, dynamic>{
      ...Map<String, dynamic>.from(row),
      'id': user.id,
      'email': user.email ?? row['email'] ?? '',
    });
  }

  Future<void> restoreSession() async {
    final client = _client;
    if (client == null) {
      _currentUser = null;
      return;
    }
    final user = client.auth.currentUser;
    if (user == null) {
      _currentUser = null;
      return;
    }
    _currentUser = await _loadProfile(user) ?? AppUser(
      id: user.id,
      email: user.email ?? '',
      name: (user.userMetadata?['full_name'] ?? '').toString(),
      role: UserRole.member,
    );
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client != null) {
      final response = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) throw const AuthException('로그인에 실패했습니다.');
      _currentUser = await _loadProfile(user) ?? AppUser(
        id: user.id,
        email: user.email ?? email.trim(),
        name: (user.userMetadata?['full_name'] ?? '').toString(),
        role: UserRole.member,
      );
      return _currentUser!;
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final match = _mockAccounts.where(
      (account) =>
          account.email == email.trim().toLowerCase() &&
          account.password == password,
    );
    if (match.isEmpty) throw const AuthException('계정 또는 암호가 올바르지 않습니다.');
    final account = match.first;
    _currentUser = AppUser(
      id: account.id,
      name: account.name,
      email: account.email,
      role: account.role,
      phone: account.phone ?? '',
      company: account.company ?? '',
    );
    return _currentUser!;
  }

  Future<void> signOut() async {
    final client = _client;
    if (client != null) await client.auth.signOut();
    _currentUser = null;
  }

  void continueAsGuest() {
    _currentUser = const AppUser(
      id: 'guest',
      name: '비회원',
      email: '',
      role: UserRole.guest,
    );
  }

  static List<MockAccountInfo> get demoAccounts => _mockAccounts
      .map(
        (account) => MockAccountInfo(
          label: account.name,
          email: account.email,
          password: account.password,
          role: account.role,
        ),
      )
      .toList(growable: false);

  Future<void> requestStaffOrPartnerAccount(
    AccountProvisionRequest request,
  ) async {
    if (request.role != UserRole.staff && request.role != UserRole.partner) {
      throw const AuthException('직원 또는 협력·파트너사 역할만 요청할 수 있습니다.');
    }
    final client = _client;
    if (client != null) {
      await client.from('account_provision_requests').insert(request.toMap());
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}


