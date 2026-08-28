import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

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
      await SupabaseService.client.auth.signOut();
      _currentUser = null;
    }
  }

  Future<AppUser?> refreshCurrentUser() async {
    if (!SupabaseConfig.isConfigured) return _currentUser;
    final authUser = SupabaseService.client.auth.currentUser;
    if (authUser == null) {
      _currentUser = null;
      return null;
    }
    try {
      _currentUser = await _loadProfile(
        authUser.id,
        fallbackEmail: authUser.email ?? '',
      );
      return _currentUser;
    } catch (_) {
      await SupabaseService.client.auth.signOut();
      _currentUser = null;
      return null;
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
      _currentUser = await _loadProfile(
        user.id,
        fallbackEmail: user.email ?? email,
      );
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
    if (pending && response.session != null) {
      await SupabaseService.client.auth.signOut();
    }

    return AuthResult(
      user: AppUser(
        id: user.id,
        email: user.email ?? email.trim(),
        name: name.trim(),
        phone: phone.trim(),
        company: company.trim(),
        role: UserRole.member,
      ),
      emailConfirmationRequired: response.session == null,
    );
  }

  /// 회원가입 확인 메일을 다시 보냅니다.
  Future<void> resendSignupEmailCode(String email) async {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthException('Supabase 설정이 필요합니다.');
    }
    await SupabaseService.client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
    );
  }

  /// Confirm signup 메일 템플릿의 {{ .Token }} 값을 확인합니다.
  /// 성공 후 profiles.email_ownership_verified_at을 기록하고
  /// 회원가입 과정에서 생성된 세션은 로그아웃하여 일반 로그인 화면으로 돌려보냅니다.
  Future<void> verifySignupEmailCode({
    required String email,
    required String code,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthException('Supabase 설정이 필요합니다.');
    }

    final response = await SupabaseService.client.auth.verifyOTP(
      type: OtpType.email,
      email: email.trim(),
      token: code.trim(),
    );

    final user = response.user;
    if (user == null) {
      throw const AuthException('이메일 인증에 실패했습니다.');
    }

    await SupabaseService.client.from('profiles').update({
      'email_ownership_verified_at':
          DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', user.id);

    await SupabaseService.client.auth.signOut();
    _currentUser = null;
  }

  Future<AppUser> updateProfile({
    required String name,
    required String phone,
    required String company,
    required String address,
  }) async {
    final authUser = SupabaseService.client.auth.currentUser;
    if (authUser == null) throw const AuthException('로그인이 필요합니다.');

    await SupabaseService.client.from('profiles').update({
      'name': name.trim(),
      'phone': phone.trim(),
      'company': company.trim(),
      'address': address.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', authUser.id);

    return (await refreshCurrentUser())!;
  }

  /// 기존 호출부 호환용. 새 계정 화면에서는 아래의
  /// updatePasswordWithVerification()을 사용합니다.
  Future<void> updatePassword(String password) async {
    if (SupabaseService.client.auth.currentUser == null) {
      throw const AuthException('로그인이 필요합니다.');
    }
    await SupabaseService.client.auth.updateUser(
      UserAttributes(password: password),
    );
  }

  /// Supabase Reauthentication 메일(OTP)을 현재 로그인 사용자의
  /// 확인된 이메일로 전송합니다.
  Future<void> sendPasswordChangeVerificationCode() async {
    final authUser = SupabaseService.client.auth.currentUser;
    if (authUser == null) throw const AuthException('로그인이 필요합니다.');
    if ((authUser.email ?? '').trim().isEmpty) {
      throw const AuthException('등록된 이메일이 없습니다.');
    }
    await SupabaseService.client.auth.reauthenticate();
  }

  /// 기존 암호 + 이메일 재인증 코드 + 새 암호를 서버에서 함께 검증합니다.
  Future<void> updatePasswordWithVerification({
    required String currentPassword,
    required String newPassword,
    required String verificationCode,
  }) async {
    final authUser = SupabaseService.client.auth.currentUser;
    if (authUser == null) throw const AuthException('로그인이 필요합니다.');

    if (currentPassword.isEmpty) {
      throw const AuthException('기존 암호를 입력해 주세요.');
    }
    if (verificationCode.trim().isEmpty) {
      throw const AuthException('이메일 인증 코드를 입력해 주세요.');
    }

    await SupabaseService.client.auth.updateUser(
      UserAttributes(
        password: newPassword,
        currentPassword: currentPassword,
        nonce: verificationCode.trim(),
      ),
    );

    await SupabaseService.client.from('profiles').update({
      'email_ownership_verified_at':
          DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', authUser.id);
  }

  Future<AppUser> uploadAvatar(XFile image) async {
    final authUser = SupabaseService.client.auth.currentUser;
    if (authUser == null) throw const AuthException('로그인이 필요합니다.');

    final bytes = await image.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw const AuthException('프로필 사진은 5MB 이하로 선택해 주세요.');
    }

    final ext = image.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final path = '${authUser.id}/avatar.$ext';

    await SupabaseService.client.storage.from('avatars').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: true),
        );

    final publicUrl =
        SupabaseService.client.storage.from('avatars').getPublicUrl(path);
    final cacheBusted =
        '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

    await SupabaseService.client.from('profiles').update({
      'avatar_url': cacheBusted,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', authUser.id);

    return (await refreshCurrentUser())!;
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
      throw const AuthException('계정 발급 요청은 직원 또는 협력·파트너사만 가능합니다.');
    }
    await SupabaseService.client
        .from('account_provision_requests')
        .insert(request.toMap());
  }

  static List<MockAccountInfo> get demoAccounts =>
      const <MockAccountInfo>[];
}
