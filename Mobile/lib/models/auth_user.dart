import 'api_exception.dart';

class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  factory AuthUser.fromJson(Object? json) {
    if (json case {
      'usuarioid': int id,
      'nombre': String name,
      'email': String email,
      'activo': bool active,
      'estado_cuenta': String? accountState,
    }) {
      if (!active || (accountState != null && accountState != 'aprobado')) {
        throw const ApiException(
          'Tu cuenta no está autorizada para acceder.',
          statusCode: 403,
        );
      }
      if (id > 0 && name.trim().isNotEmpty && email.trim().isNotEmpty) {
        return AuthUser(id: id, name: name, email: email);
      }
    }
    throw const ApiException('La API devolvió un perfil de usuario inválido.');
  }

  final int id;
  final String name;
  final String email;
}
