import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

const identity = {
  'usuarioid': 1,
  'nombre': 'Ana',
  'email': 'ana@example.test',
  'activo': true,
  'estado_cuenta': 'aprobado',
};

void main() {
  test('Conserva el contrato de perfil sin convertir CI/NIT a número', () {
    final user = AuthUser.fromJson({
      ...identity,
      'apellido': 'Mamani',
      'nombreusuario': 'ana.mamani',
      'telefono': '70000000',
      'ci_nit': '00123-A',
      'avatar_url': 'https://images.example.test/ana.png',
      'fecharegistro': '2026-10-25T16:00:00.000000Z',
      'fechamodificacion': '2026-10-26T02:00:00Z',
      'ultimologin': null,
      'roles': [
        {'id': 2, 'name': 'agricultor'},
        {'id': 3, 'name': 'planta'},
      ],
      'permissions': ['lotes.view', 'inventario.view', 'lotes.view'],
      'nombreusuario_editado': true,
      'profile_capabilities': {'update_username': false, 'update_photo': true},
    });
    expect(user.fullName, 'Ana Mamani');
    expect(user.username, 'ana.mamani');
    expect(user.phone, '70000000');
    expect(user.identityDocument, '00123-A');
    expect(user.avatarUrl, 'https://images.example.test/ana.png');
    expect(user.registeredAt, DateTime.utc(2026, 10, 25, 16));
    expect(user.updatedAt, DateTime.utc(2026, 10, 26, 2));
    expect(user.lastLoginAt, isNull);
    expect(user.roles, ['agricultor', 'planta']);
    expect(user.permissions, {'lotes.view', 'inventario.view'});
    expect(user.usernameEdited, isTrue);
    expect(user.canUpdateUsername, isFalse);
    expect(user.canUpdatePhoto, isTrue);
  });

  test(
    'Un rol admin sin permisos ni capacidades no obtiene autorizaciones',
    () {
      final user = AuthUser.fromJson({
        ...identity,
        'roles': [
          {'name': 'admin'},
        ],
      });
      expect(user.fullName, 'Ana');
      expect(user.permissions, isEmpty);
      expect(user.canUpdateUsername, isFalse);
      expect(user.canUpdatePhoto, isFalse);
    },
  );

  test('Acepta campos opcionales ausentes y una cuenta heredada activa', () {
    final user = AuthUser.fromJson({
      ...identity,
      'estado_cuenta': null,
      'apellido': '',
      'telefono': null,
      'ultimologin': '',
      'roles': [],
      'permissions': [],
    });
    expect(user.lastName, isNull);
    expect(user.phone, isNull);
    expect(user.lastLoginAt, isNull);
    expect(user.roles, isEmpty);
  });

  test('Rechaza tipos de perfil inválidos con un error controlado', () {
    for (final extra in <Map<String, Object?>>[
      {'ci_nit': 123},
      {'apellido': false},
      {'fecharegistro': 'fecha inválida'},
      {'roles': 'admin'},
      {
        'roles': [
          {'id': 2},
        ],
      },
      {
        'roles': [
          {'name': ''},
        ],
      },
      {
        'permissions': ['lotes.view', true],
      },
      {
        'permissions': [' '],
      },
      {'profile_capabilities': true},
      {
        'profile_capabilities': {'update_photo': 'true'},
      },
      {'nombreusuario_editado': 1},
    ]) {
      expect(
        () => AuthUser.fromJson({...identity, ...extra}),
        throwsA(isA<ApiException>()),
        reason: extra.toString(),
      );
    }
  });

  test(
    'Una respuesta no puede cambiar roles o permisos después de validarla',
    () {
      final roles = [
        {'name': 'agricultor'},
      ];
      final permissions = ['lotes.view'];
      final user = AuthUser.fromJson({
        ...identity,
        'roles': roles,
        'permissions': permissions,
      });
      roles.clear();
      permissions.add('usuarios.admin');
      expect(user.roles, ['agricultor']);
      expect(user.permissions, {'lotes.view'});
      expect(() => user.roles.add('admin'), throwsUnsupportedError);
      expect(
        () => user.permissions.add('usuarios.admin'),
        throwsUnsupportedError,
      );
    },
  );
}
