import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/logout_result.dart';
import '../models/registration_result.dart';
import '../services/auth_service.dart';

enum _AuthOperation { idle, restoring, profile, login, register, logout }

class AuthController extends ChangeNotifier {
  static const _expiredError = ApiException(
    'La sesión dejó de ser válida. Inicia sesión de nuevo.',
    statusCode: 401,
  );

  AuthController(this._service) {
    _expirationSubscription = _service.sessionExpired.listen(_sessionExpired);
  }

  final AuthService _service;
  late final StreamSubscription<bool> _expirationSubscription;
  AuthUser? _user;
  ApiException? _error;
  ApiException? _sessionError;
  _AuthOperation _operation = _AuthOperation.idle;
  LogoutResult? _logoutResult;
  bool _isDisposed = false;

  AuthUser? get user => _user;
  ApiException? get error => _error;
  bool get isSubmitting => _operation != _AuthOperation.idle;
  bool get isLoggingOut => _operation == _AuthOperation.logout;
  bool get isCheckingSession => _operation == _AuthOperation.restoring;
  bool get isLoadingProfile => _operation == _AuthOperation.profile;
  ApiException? get sessionError => _sessionError;
  LogoutResult? get logoutResult => _logoutResult;
  bool get requiresLogoutRetry => _logoutResult?.localCleared == false;

  void _sessionExpired(bool localCleared) {
    if (_isDisposed || _user == null || isSubmitting) return;
    _user = null;
    _sessionError = null;
    if (localCleared) {
      _logoutResult = null;
      _error = _expiredError;
    } else {
      _error = null;
      _logoutResult = const LogoutResult(
        localCleared: false,
        remoteClosed: true,
      );
    }
    notifyListeners();
  }

  Future<void> restoreSession() => _verifySession();

  Future<void> refreshProfile() async {
    final user = _user;
    if (user != null) await _verifySession(expectedId: user.id);
  }

  Future<void> _verifySession({int? expectedId}) async {
    if (isSubmitting || _isDisposed || requiresLogoutRetry) return;
    _operation = expectedId == null
        ? _AuthOperation.restoring
        : _AuthOperation.profile;
    if (expectedId == null) _user = null;
    _error = null;
    _sessionError = null;
    _logoutResult = null;
    notifyListeners();
    try {
      final user = await _service.restoreSession();
      if (_isDisposed) return;
      if (expectedId != null) {
        if (user == null) throw _expiredError;
        if (user.id != expectedId) {
          throw const ApiException('La API devolvió un perfil de otra cuenta.');
        }
      }
      _user = user;
    } on ApiException catch (error) {
      if (_isDisposed) return;
      _user = null;
      if (error.statusCode == 401) {
        _error = _expiredError;
      } else if (error.statusCode == 403) {
        _error = error;
      } else {
        _sessionError = error;
      }
    } finally {
      _operation = _AuthOperation.idle;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> logout() async {
    if (isSubmitting || _isDisposed) return;
    _operation = _AuthOperation.logout;
    _user = null;
    _error = null;
    _sessionError = null;
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
    if (isSubmitting ||
        _isDisposed ||
        requiresLogoutRetry ||
        _sessionError != null) {
      return null;
    }
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
    if (isSubmitting ||
        _isDisposed ||
        requiresLogoutRetry ||
        _sessionError != null) {
      return false;
    }
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
    unawaited(_expirationSubscription.cancel());
    super.dispose();
  }
}
