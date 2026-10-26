import 'api_exception.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.lastName,
    this.username,
    this.phone,
    this.identityDocument,
    this.avatarUrl,
    this.registeredAt,
    this.updatedAt,
    this.lastLoginAt,
    this.roles = const [],
    this.permissions = const {},
    this.usernameEdited = false,
    this.canUpdateUsername = false,
    this.canUpdatePhoto = false,
  });

  factory AuthUser.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) throw _invalidProfile;
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
        final fields = json;
        final roleNames = <String>{};
        final roles = fields['roles'];
        if (roles != null) {
          if (roles is! List) throw _invalidProfile;
          for (final role in roles) {
            if (role case {
              'name': String roleName,
            } when roleName.trim().isNotEmpty) {
              roleNames.add(roleName);
            } else {
              throw _invalidProfile;
            }
          }
        }
        final permissions = fields['permissions'];
        if (permissions != null &&
            (permissions is! List ||
                permissions.any(
                  (value) => value is! String || value.trim().isEmpty,
                ))) {
          throw _invalidProfile;
        }
        final capabilities = fields['profile_capabilities'];
        if (capabilities != null && capabilities is! Map<String, dynamic>) {
          throw _invalidProfile;
        }
        return AuthUser(
          id: id,
          name: name,
          email: email,
          lastName: _text(fields, 'apellido'),
          username: _text(fields, 'nombreusuario'),
          phone: _text(fields, 'telefono'),
          identityDocument: _text(fields, 'ci_nit'),
          avatarUrl: _text(fields, 'avatar_url'),
          registeredAt: _date(fields, 'fecharegistro'),
          updatedAt: _date(fields, 'fechamodificacion'),
          lastLoginAt: _date(fields, 'ultimologin'),
          roles: List.unmodifiable(roleNames),
          permissions: Set.unmodifiable(
            (permissions as List?)?.cast<String>() ?? <String>[],
          ),
          usernameEdited: _flag(fields, 'nombreusuario_editado'),
          canUpdateUsername: _flag(capabilities, 'update_username'),
          canUpdatePhoto: _flag(capabilities, 'update_photo'),
        );
      }
    }
    throw _invalidProfile;
  }

  final int id;
  final String name;
  final String email;
  final String? lastName;
  final String? username;
  final String? phone;
  final String? identityDocument;
  final String? avatarUrl;
  final DateTime? registeredAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;
  final List<String> roles;
  final Set<String> permissions;
  final bool usernameEdited;
  final bool canUpdateUsername;
  final bool canUpdatePhoto;

  String get fullName => [name, ?lastName].join(' ');

  static const _invalidProfile = ApiException(
    'La API devolvió un perfil de usuario inválido.',
  );

  static String? _text(Map<String, dynamic> fields, String key) {
    final value = fields[key];
    if (value == null) return null;
    if (value is! String) throw _invalidProfile;
    return value.trim().isEmpty ? null : value;
  }

  static DateTime? _date(Map<String, dynamic> fields, String key) {
    final text = _text(fields, key);
    if (text == null) return null;
    final date = DateTime.tryParse(text);
    if (date == null) throw _invalidProfile;
    return date;
  }

  static bool _flag(Map<String, dynamic>? fields, String key) {
    final value = fields?[key];
    if (value == null) return false;
    if (value is! bool) throw _invalidProfile;
    return value;
  }
}
