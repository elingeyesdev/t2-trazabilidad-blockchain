import 'package:flutter/foundation.dart';

import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/registration_result.dart';
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._service);

  final AuthService _service;
  AuthUser? _user;
  ApiException? _error;
  bool _isSubmitting = false;
  bool _isDisposed = false;

  AuthUser? get user => _user;
  ApiException? get error => _error;
  bool get isSubmitting => _isSubmitting;

  Future<RegistrationResult?> register({
    required String name,
    required String lastName,
    required String email,
    required String username,
    required String password,
    String phone = '',
  }) async {
    if (_isSubmitting || _isDisposed) return null;
    _isSubmitting = true;
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
      _isSubmitting = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    if (_isSubmitting || _isDisposed) return false;
    _isSubmitting = true;
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
      _isSubmitting = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  void clearError() {
    if (_error == null || _isDisposed) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
