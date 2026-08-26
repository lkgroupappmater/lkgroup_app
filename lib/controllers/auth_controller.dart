// lib/controllers/auth_controller.dart
//
// ChangeNotifier 기반 AuthController.
// provider 패키지 없이 InheritedNotifier / ListenableBuilder 로 사용합니다.

import 'package:flutter/foundation.dart';
import '../models/app_user.dart' hide AuthException;
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController() {
    _init();
  }

  final AuthService _service = AuthService.instance;

  AppUser _user = const AppUser(
    id: 'guest',
    name: '게스트',
    email: '',
    role: UserRole.guest,
    company: null,
    avatarUrl: null,
  );
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _errorMessage;

  AppUser get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _service.isAuthenticated;

  bool get hasEnteredApp =>
      _user.role != UserRole.guest || _guestBrowsing;

  bool _guestBrowsing = false;
  bool get guestBrowsing => _guestBrowsing;

  Future<void> _init() async {
    _isInitializing = true;
    notifyListeners();

    try {
      await _service.restoreSession();
      final restored = _service.currentUser;
      if (restored != null) {
        _user = restored;
      }
    } catch (_) {
      // 세션 복원 실패 시 guest 상태를 유지합니다.
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

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
    } catch (e) {
      final message = e
          .toString()
          .replaceFirst('AuthException: ', '')
          .replaceFirst('Exception: ', '')
          .trim();
      _errorMessage = message.isEmpty ? '알 수 없는 오류가 발생했습니다.' : message;
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

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

  void browseAsGuest() {
    _service.continueAsGuest();
    _guestBrowsing = true;
    _clearError();
    notifyListeners();
  }

  void clearError() => _clearError();

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

