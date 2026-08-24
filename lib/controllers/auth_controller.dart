// lib/controllers/auth_controller.dart
//
// ChangeNotifier 기반 AuthController.
// provider 패키지 없이 InheritedNotifier / ListenableBuilder 로 사용합니다.

import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController() {
    // 앱 시작 시 자동 로그인 시도
    _init();
  }

  final AuthService _service = AuthService.instance;

  // ── 상태 ────────────────────────────────────────────────────────────────
  AppUser _user = const AppUser(
    id: 'guest',
    name: '게스트',
    email: '',
    role: UserRole.guest,
    company: null,
    avatarUrl: null,
  );
  bool _isLoading = false;
  bool _isInitializing = true; // 세션 복원 중
  String? _errorMessage;

  // ── 공개 게터 ────────────────────────────────────────────────────────────
  AppUser get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _service.isAuthenticated;

  /// guest 포함 "진입 허용" 여부 (로그인 화면을 건너뛸 조건)
  bool get hasEnteredApp =>
      _user.role != UserRole.guest || _guestBrowsing;

  // 게스트 둘러보기 모드 플래그
  bool _guestBrowsing = false;
  bool get guestBrowsing => _guestBrowsing;

  // ── 초기화: 세션 복원 ────────────────────────────────────────────────────
  // [SUPABASE] Supabase.instance.client.auth.onAuthStateChange 스트림을 listen 해도 됩니다.
  Future<void> _init() async {
    _isInitializing = true;
    notifyListeners();

    try {
      final restored = await _service.restoreSession();
      _user = restored;
    } catch (_) {
      // 세션 복원 실패 → guest 유지
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  // ── 로그인 ───────────────────────────────────────────────────────────────
  /// 반환값: 성공 여부
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final user = await _service.signIn(email: email, password: password);
      _user = user;
      _guestBrowsing = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = '알 수 없는 오류가 발생했습니다.';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ── 로그아웃 ─────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    _setLoading(true);
    try {
      await _service.signOut();
      _user = const AppUser(
        id: 'guest',
        name: '게스트',
        email: '',
        role: UserRole.guest,
        company: null,
        avatarUrl: null,
      );
      _guestBrowsing = false;
      _clearError();
    } finally {
      _setLoading(false);
    }
  }

  // ── 게스트 둘러보기 ───────────────────────────────────────────────────────
  void browseAsGuest() {
    _service.continueAsGuest();
    _guestBrowsing = true;
    _clearError();
    notifyListeners();
  }

  // ── 에러 초기화 ──────────────────────────────────────────────────────────
  void clearError() => _clearError();

  // ── 내부 헬퍼 ────────────────────────────────────────────────────────────
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}


