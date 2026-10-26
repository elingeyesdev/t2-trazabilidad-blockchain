import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/logout_result.dart';
import '../models/profile_photo.dart';
import '../models/registration_result.dart';
import 'api_client.dart';
import 'session_storage.dart';

class AuthService {
  AuthService(this._api, this._storage);

  final ApiClient _api;
  final SessionStorage _storage;

  Stream<bool> get sessionExpired => _api.sessionExpired;

  Future<AuthUser> updateProfile({
    required int userId,
    String? username,
    ProfilePhoto? photo,
  }) async {
    if (username == null && photo == null) {
      throw const ApiException('No hay cambios para guardar.');
    }
    final token = await _readToken();
    if (token == null) {
      throw const ApiException(
        'La sesión no es válida. Inicia sesión de nuevo.',
        statusCode: 401,
      );
    }
    final response = photo == null
        ? await _api.request(
            'PATCH',
            'me',
            bearerToken: token,
            body: {'nombreusuario': username!.trim()},
          )
        : await _api.request(
            'POST',
            'me',
            bearerToken: token,
            fields: {
              '_method': 'PATCH',
              if (username != null) 'nombreusuario': username.trim(),
            },
            files: [
              http.MultipartFile.fromBytes(
                'imagen',
                photo.bytes,
                filename: photo.filename,
                contentType: http.MediaType.parse(photo.contentType),
              ),
            ],
          );
    if (await _readToken() != token) {
      throw const ApiException(
        'La sesión cambió durante el guardado. Consulta el perfil de nuevo.',
      );
    }
    late final AuthUser user;
    try {
      user = AuthUser.fromJson(response);
    } on ApiException {
      throw const ApiException(
        'No se pudo confirmar el perfil actualizado. Consulta el perfil de nuevo.',
      );
    }
    if (user.id != userId) {
      throw const ApiException(
        'No se pudo confirmar el perfil actualizado. Consulta el perfil de nuevo.',
      );
    }
    return user;
  }

  Future<AuthUser?> restoreSession() async {
    final token = await _readToken();
    if (token == null) return null;
    try {
      return await _loadUser(token);
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        bool cleared;
        try {
          cleared = await _clearTokenIfCurrent(token);
        } catch (_) {
          throw const ApiException(
            'No se pudo limpiar el almacenamiento de sesión. Intenta de nuevo.',
          );
        }
        if (!cleared) {
          throw const ApiException(
            'La sesión cambió mientras se verificaba. Reintenta.',
          );
        }
      }
      rethrow;
    }
  }

  Future<String?> _readToken() async {
    try {
      return await _storage.readToken();
    } catch (_) {
      throw const ApiException(
        'No se pudo acceder al almacenamiento de sesión. Intenta de nuevo.',
      );
    }
  }

  Future<bool> _clearTokenIfCurrent(String token) async {
    final current = await _storage.readToken();
    if (current == null) return true;
    if (current != token) return false;
    await _storage.clearToken();
    return true;
  }

  Future<AuthUser> _loadUser(String token) async {
    final user = AuthUser.fromJson(
      await _api.request('GET', 'me', bearerToken: token),
    );
    if (await _readToken() != token) {
      throw const ApiException(
        'La sesión cambió mientras se verificaba. Reintenta.',
      );
    }
    return user;
  }

  Future<LogoutResult> logout() async {
    String? token;
    var tokenKnown = false;
    var remoteClosed = false;
    var localCleared = false;
    try {
      token = await _storage.readToken();
      tokenKnown = true;
      if (token == null) {
        remoteClosed = true;
      } else {
        await _api.request('POST', 'logout', bearerToken: token);
        remoteClosed = true;
      }
    } on ApiException catch (error) {
      remoteClosed = error.statusCode == 401;
    } catch (_) {
      remoteClosed = false;
    } finally {
      try {
        if (!tokenKnown || await _storage.readToken() == token) {
          await _storage.clearToken();
        }
        localCleared = true;
      } catch (_) {
        localCleared = false;
      }
    }
    return LogoutResult(localCleared: localCleared, remoteClosed: remoteClosed);
  }

  Future<RegistrationResult> register({
    required String name,
    required String lastName,
    required String email,
    required String username,
    required String password,
    String phone = '',
  }) async {
    final response = await _api.request(
      'POST',
      'register',
      authenticated: false,
      body: {
        'nombre': name.trim(),
        'apellido': lastName.trim(),
        'email': email.trim(),
        'nombreusuario': username.trim(),
        'password': password,
        if (phone.trim().isNotEmpty) 'telefono': phone.trim(),
      },
    );
    return RegistrationResult.fromJson(response);
  }

  Future<AuthUser> login(String email, String password) async {
    final response = await _api.request(
      'POST',
      'login',
      body: {'email': email.trim(), 'password': password},
      authenticated: false,
    );
    if (response is! Map<String, dynamic> ||
        response['token'] is! String ||
        (response['token'] as String).isEmpty ||
        RegExp(r'\s').hasMatch(response['token'] as String)) {
      throw const ApiException('La API devolvió una sesión inválida.');
    }
    final loginUser = AuthUser.fromJson(response['user']);
    final token = response['token'] as String;

    try {
      await _storage.saveToken(token);
      final user = await _loadUser(token);
      if (user.id != loginUser.id) {
        throw const ApiException(
          'La API devolvió un perfil de usuario inválido.',
        );
      }
      return user;
    } catch (error) {
      try {
        await _clearTokenIfCurrent(token);
      } catch (_) {
        throw const ApiException(
          'No se pudo limpiar el almacenamiento de sesión. Intenta de nuevo.',
        );
      }
      if (error is PlatformException) {
        throw const ApiException(
          'No se pudo guardar la sesión. Intenta de nuevo.',
        );
      }
      rethrow;
    }
  }
}
