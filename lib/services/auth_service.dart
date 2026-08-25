// lib/services/auth_service.dart
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../models/app_user.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();
  sb.SupabaseClient get _client => sb.Supabase.instance.client;
  AppUser _currentUser = const AppUser(id: 'guest', name: '게스트', role: UserRole.guest);
  AppUser get currentUser => _currentUser;
  bool get isAuthenticated => _client.auth.currentUser != null && _currentUser.role != UserRole.guest;

  Future<AppUser> _profileFor(sb.User user) async {
    try { final row = await _client.from('profiles').select().eq('id', user.id).maybeSingle(); if (row != null) return AppUser.fromMap(Map<String, dynamic>.from(row)); } catch (_) {}
    return AppUser(id: user.id, email: user.email ?? '', name: user.userMetadata?['full_name']?.toString() ?? '', phone: user.phone ?? '', role: UserRole.member);
  }

  Future<AppUser> signIn({required String email, required String password}) async {
    try { final response = await _client.auth.signInWithPassword(email: email.trim(), password: password); final user = response.user; if (user == null) throw const AuthException('로그인에 실패했습니다.'); _currentUser = await _profileFor(user); return _currentUser; }
    on AuthException { rethrow; } on sb.AuthApiException catch (error) { throw AuthException(error.message); } catch (_) { throw const AuthException('로그인 중 오류가 발생했습니다.'); }
  }

  Future<AuthResult> signUpGeneral({required String name, required String email, required String password, required String countryCode, required String phone, required String address}) async {
    if (name.trim().isEmpty || email.trim().isEmpty || password.length < 6 || phone.trim().isEmpty || address.trim().isEmpty) throw const AuthException('이름, 이메일, 암호(6자 이상), 연락처, 주소를 모두 입력해 주세요.');
    try {
      final response = await _client.auth.signUp(email: email.trim(), password: password, data: {'full_name': name.trim(), 'phone': phone.trim(), 'country_code': countryCode, 'address': address.trim(), 'role': 'member'});
      final user = response.user; if (user == null) throw const AuthException('회원가입에 실패했습니다.');
      final profile = AppUser(id: user.id, email: email.trim(), name: name.trim(), phone: phone.trim(), countryCode: countryCode, address: address.trim(), role: UserRole.member);
      return AuthResult(user: profile, emailConfirmationRequired: response.session == null);
    } on AuthException { rethrow; } on sb.AuthApiException catch (error) { throw AuthException(error.message); } catch (_) { throw const AuthException('회원가입 중 오류가 발생했습니다.'); }
  }

  Future<AppUser> restoreSession() async { final user = _client.auth.currentUser; if (user == null) { _currentUser = const AppUser(id: 'guest', name: '게스트', role: UserRole.guest); return _currentUser; } _currentUser = await _profileFor(user); return _currentUser; }
  Future<void> signOut() async { await _client.auth.signOut(); _currentUser = const AppUser(id: 'guest', name: '게스트', role: UserRole.guest); }
  Future<void> requestStaffOrPartnerAccount(AccountProvisionRequest request) async { if (_currentUser.role != UserRole.admin) throw const AuthException('총괄 관리자만 관리자 계정을 신청할 수 있습니다.'); await _client.from('account_provision_requests').insert(request.toMap()); }
  static List<MockAccountInfo> get demoAccounts => const [];
}
