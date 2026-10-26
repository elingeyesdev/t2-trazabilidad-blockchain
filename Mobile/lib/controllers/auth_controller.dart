import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/logout_result.dart';
import '../models/profile_photo.dart';
import '../models/registration_result.dart';
import '../services/auth_service.dart';

enum _AuthOperation {
  idle,
  restoring,
  profile,
  pickingPhoto,
  savingProfile,
  login,
  register,
  logout,
}

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
  int? _sessionUserId;
  int _sessionRevision = 0;
  ApiException? _error;
  ApiException? _sessionError;
  _AuthOperation _operation = _AuthOperation.idle;
  LogoutResult? _logoutResult;
  bool _isDisposed = false;
  bool _profileUpdateNeedsRefresh = false;

  AuthUser? get user => _user;
  ApiException? get error => _error;
  bool get isSubmitting => _operation != _AuthOperation.idle;
  bool get isLoggingOut => _operation == _AuthOperation.logout;
  bool get isCheckingSession => _operation == _AuthOperation.restoring;
  bool get isLoadingProfile => _operation == _AuthOperation.profile;
  bool get isSavingProfile => _operation == _AuthOperation.savingProfile;
  bool get profileUpdateNeedsRefresh => _profileUpdateNeedsRefresh;
  ApiException? get sessionError => _sessionError;
  LogoutResult? get logoutResult => _logoutResult;
  bool get requiresLogoutRetry => _logoutResult?.localCleared == false;

  bool _canApplyResult(int revision) =>
      !_isDisposed && revision == _sessionRevision;

  void _sessionExpired(bool localCleared) {
    final handlesItsOwnErrors =
        _operation == _AuthOperation.login ||
        _operation == _AuthOperation.register ||
        _operation == _AuthOperation.logout;
    if (_isDisposed ||
        handlesItsOwnErrors ||
        (_user == null && _sessionUserId == null && !isCheckingSession)) {
      return;
    }
    _sessionRevision++;
    _user = null;
    _sessionUserId = null;
    _sessionError = null;
    _profileUpdateNeedsRefresh = false;
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

  Future<ProfilePhoto?> selectProfilePhoto(
    Future<ProfilePhoto?> Function() select,
  ) async {
    if (isSubmitting || _isDisposed || _user?.canUpdatePhoto != true) {
      return null;
    }
    final revision = _sessionRevision;
    _operation = _AuthOperation.pickingPhoto;
    _error = null;
    notifyListeners();
    ProfilePhoto? photo;
    try {
      photo = await select();
    } on ApiException catch (error) {
      if (_canApplyResult(revision)) _error = error;
    } catch (_) {
      if (_canApplyResult(revision)) {
        _error = const ApiException(
          'No se pudo abrir o leer la fotografía. Intenta de nuevo.',
        );
      }
    } finally {
      _operation = _AuthOperation.idle;
      if (!_isDisposed) notifyListeners();
    }
    if (!_canApplyResult(revision)) return null;
    if (_user != null) await refreshProfile(keepError: true);
    return !_isDisposed && _user?.canUpdatePhoto == true ? photo : null;
  }

  Future<bool> updateProfile({String? username, ProfilePhoto? photo}) async {
    final current = _user;
    if (isSubmitting ||
        _isDisposed ||
        current == null ||
        requiresLogoutRetry ||
        _sessionError != null ||
        _profileUpdateNeedsRefresh) {
      return false;
    }
    if ((username != null && !current.canUpdateUsername) ||
        (photo != null && !current.canUpdatePhoto)) {
      _error = const ApiException(
        'No tienes permiso para realizar este cambio de perfil.',
        statusCode: 403,
      );
      notifyListeners();
      return false;
    }
    _operation = _AuthOperation.savingProfile;
    final revision = _sessionRevision;
    _error = null;
    notifyListeners();
    try {
      final user = await _service.updateProfile(
        userId: current.id,
        username: username,
        photo: photo,
      );
      if (!_canApplyResult(revision)) return false;
      _user = user;
      _profileUpdateNeedsRefresh = false;
      return true;
    } on ApiException catch (error) {
      if (!_canApplyResult(revision)) return false;
      if (error.statusCode == 401) {
        _user = null;
        _sessionUserId = null;
        _error = _expiredError;
      } else {
        _error = error;
        _profileUpdateNeedsRefresh =
            error.statusCode == null || error.statusCode! >= 500;
      }
      return false;
    } finally {
      _operation = _AuthOperation.idle;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> refreshProfile({bool keepError = false}) async {
    if (_user != null) {
      await _verifySession(profileOnly: true, keepError: keepError);
    }
  }

  Future<void> _verifySession({
    bool profileOnly = false,
    bool keepError = false,
  }) async {
    if (isSubmitting || _isDisposed || requiresLogoutRetry) return;
    final expectedId = _sessionUserId;
    final revision = _sessionRevision;
    _operation = profileOnly
        ? _AuthOperation.profile
        : _AuthOperation.restoring;
    if (!profileOnly) _user = null;
    if (!keepError) _error = null;
    _sessionError = null;
    _logoutResult = null;
    notifyListeners();
    try {
      final user = await _service.restoreSession();
      if (!_canApplyResult(revision)) return;
      if (expectedId != null) {
        if (user == null) throw _expiredError;
        if (user.id != expectedId) {
          throw const ApiException('La API devolvió un perfil de otra cuenta.');
        }
      }
      _user = user;
      _sessionUserId = user?.id;
      _profileUpdateNeedsRefresh = false;
    } on ApiException catch (error) {
      if (!_canApplyResult(revision)) return;
      _user = null;
      if (error.statusCode == 401) {
        _sessionUserId = null;
        _error = _expiredError;
      } else if (error.statusCode == 403) {
        _sessionUserId = null;
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
    _sessionUserId = null;
    _profileUpdateNeedsRefresh = false;
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
    _sessionUserId = null;
    _error = null;
    notifyListeners();

    try {
      _user = await _service.login(email, password);
      _sessionUserId = _user!.id;
      _profileUpdateNeedsRefresh = false;
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
