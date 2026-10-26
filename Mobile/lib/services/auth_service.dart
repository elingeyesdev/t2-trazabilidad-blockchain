import 'package:flutter/services.dart';

import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/registration_result.dart';
import 'api_client.dart';
import 'session_storage.dart';

class AuthService {
  AuthService(this._api, this._storage);

  final ApiClient _api;
  final SessionStorage _storage;

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
      final user = AuthUser.fromJson(await _api.request('GET', 'me'));
      if (user.id != loginUser.id) {
        throw const ApiException(
          'La API devolvió un perfil de usuario inválido.',
        );
      }
      return user;
    } catch (error) {
      try {
        await _storage.clearToken();
      } on PlatformException {
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
