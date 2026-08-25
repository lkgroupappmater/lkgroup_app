import 'package:flutter/foundation.dart';
import '../models/app_user.dart' hide AuthException;
import '../services/auth_service.dart';

/// Authentication state controller. The mock service can be replaced with
/// Supabase Auth without changing the screens.
class AuthController extends ChangeNotifier {
  AuthController() { _init(); }

  final AuthService _service = AuthService.instance;
  AppUser _user = const AppUser(
    id: 'guest', name: '게스트', email: '', role: UserRole.guest,
  );
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _guestBrowsing = false;
  String? _errorMessage;

  AppUser get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _service.isAuthenticated;
  bool get hasEnteredApp => _user.role != UserRole.guest || _guestBrowsing;
  bool get guestBrowsing => _guestBrowsing;

  Future<void> _init() async {
    try {
      await _service.restoreSession();
      final restored = _service.currentUser;
      if (restored != null) _user = restored;
    } catch (_) {
      // Guest state is retained when session restore is unavailable.
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    _setLoading(true);
    _clearError();
    try {
      _user = await _service.signIn(email: email, password: password);
      _guestBrowsing = false;
      notifyListeners();
      return true;
    } catch (error) {
      _errorMessage = error.toString()
          .replaceFirst('AuthException: ', '')
          .replaceFirst('Exception: ', '');
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
        id: 'guest', name: '게스트', email: '', role: UserRole.guest,
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
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}
