import 'package:flutter/foundation.dart';

import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/logout_result.dart';
import '../models/registration_result.dart';
import '../services/auth_service.dart';

enum _AuthOperation { idle, login, register, logout }

class AuthController extends ChangeNotifier {
  AuthController(this._service);

  final AuthService _service;
  AuthUser? _user;
  ApiException? _error;
  _AuthOperation _operation = _AuthOperation.idle;
  LogoutResult? _logoutResult;
  bool _isDisposed = false;

  AuthUser? get user => _user;
  ApiException? get error => _error;
  bool get isSubmitting => _operation != _AuthOperation.idle;
  bool get isLoggingOut => _operation == _AuthOperation.logout;
  LogoutResult? get logoutResult => _logoutResult;
  bool get requiresLogoutRetry => _logoutResult?.localCleared == false;

  Future<void> logout() async {
    if (isSubmitting || _isDisposed) return;
    _operation = _AuthOperation.logout;
    _user = null;
    _error = null;
    _logoutResult = null;
    notifyListeners();
    try {
      _logoutResult = await _service.logout();
    } finally {
      _operation = _AuthOperation.idle;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<RegistrationResult?> register({
    required String name,
    required String lastName,
    required String email,
    required String username,
    required String password,
    String phone = '',
  }) async {
    if (isSubmitting || _isDisposed || requiresLogoutRetry) return null;
    _operation = _AuthOperation.register;
    _logoutResult = null;
    _error = null;
    notifyListeners();

    try {
      return await _service.register(
        name: name,
        lastName: lastName,
        email: email,
        username: username,
        password: password,
        phone: phone,
      );
    } on ApiException catch (error) {
      _error = error;
      return null;
    } finally {
      _operation = _AuthOperation.idle;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    if (isSubmitting || _isDisposed || requiresLogoutRetry) return false;
    _operation = _AuthOperation.login;
    _logoutResult = null;
    _user = null;
    _error = null;
    notifyListeners();

    try {
      _user = await _service.login(email, password);
      return true;
    } on ApiException catch (error) {
      _error = error;
      return false;
    } finally {
      _operation = _AuthOperation.idle;
      if (!_isDisposed) notifyListeners();
    }
  }

  void clearError() {
    if (_isDisposed ||
        requiresLogoutRetry ||
        (_error == null && _logoutResult == null)) {
      return;
    }
    _error = null;
    _logoutResult = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
