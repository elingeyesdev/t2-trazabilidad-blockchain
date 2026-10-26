import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/auth_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const profile = {
  'usuarioid': 1,
  'nombre': 'Ana',
  'email': 'ana@example.test',
  'activo': true,
  'estado_cuenta': 'aprobado',
};

class UnwritableSessionStorage extends SessionStorage {
  @override
  Future<void> saveToken(String token) async {
    throw PlatformException(code: 'storage-unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = SessionStorage();

  AuthService serviceWith(
    Future<http.Response> Function(http.Request) handler, {
    SessionStorage session = storage,
  }) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: session,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    return AuthService(api, session);
  }

  http.Response jsonResponse(Object? data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  const pending = {
    'message': 'Solicitud registrada. La cuenta queda pendiente de aprobación.',
    'user': {'email': 'ana@example.test', 'estado_cuenta': 'pendiente'},
  };

  Future<Object?> register(AuthService service, {String phone = ''}) =>
      service.register(
        name: ' Ana ',
        lastName: ' Mamani ',
        email: ' ana@example.test ',
        username: ' ana.mamani ',
        password: ' clave sin recortar ',
        phone: phone,
      );

  test(
    'El registro envía los campos de Laravel sin Bearer ni cambio de sesión',
    () async {
      await storage.saveToken('9|sesion-anterior');
      final service = serviceWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/register');
        expect(request.headers['Authorization'], isNull);
        expect(jsonDecode(request.body), {
          'nombre': 'Ana',
          'apellido': 'Mamani',
          'email': 'ana@example.test',
          'nombreusuario': 'ana.mamani',
          'password': ' clave sin recortar ',
          'telefono': '70000000',
        });
        return jsonResponse(pending, 201);
      });
      final result = await register(service, phone: ' 70000000 ');
      expect(result, isNotNull);
      expect(await storage.readToken(), '9|sesion-anterior');
      expect(await const FlutterSecureStorage().readAll(), {
        'agrofusion.auth_token': '9|sesion-anterior',
      });
    },
  );

  test('El registro pendiente sin teléfono no guarda credenciales', () async {
    final service = serviceWith((request) async {
      expect(
        (jsonDecode(request.body) as Map).containsKey('telefono'),
        isFalse,
      );
      return jsonResponse(pending, 201);
    });
    final result = await service.register(
      name: 'Ana',
      lastName: 'Mamani',
      email: 'ana@example.test',
      username: 'ana',
      password: 'secreto',
    );
    expect(result.email, 'ana@example.test');
    expect(result.message, pending['message']);
    expect(await storage.readToken(), isNull);
  });

  test(
    'Rechaza confirmaciones que no representan una solicitud pendiente sin token',
    () async {
      for (final response in [
        null,
        {},
        {'message': 'Solicitud registrada', 'user': profile},
        {...pending, 'token': '1|token-no-esperado'},
        {...pending, 'message': ''},
        {
          ...pending,
          'user': {'email': '', 'estado_cuenta': 'pendiente'},
        },
      ]) {
        final service = serviceWith((_) async => jsonResponse(response, 201));
        await expectLater(register(service), throwsA(isA<ApiException>()));
        expect(await storage.readToken(), isNull);
      }
    },
  );

  test(
    'Conserva los errores de registro por campo sin alterar una sesión previa',
    () async {
      await storage.saveToken('9|sesion-anterior');
      final service = serviceWith(
        (_) async => jsonResponse({
          'message': 'Revisa los datos enviados.',
          'errors': {
            'nombreusuario': ['Ese nombre de usuario ya está en uso.'],
          },
        }, 422),
      );
      await expectLater(
        register(service),
        throwsA(
          isA<ApiException>().having(
            (error) => error.validationErrors['nombreusuario'],
            'nombreusuario',
            ['Ese nombre de usuario ya está en uso.'],
          ),
        ),
      );
      expect(await storage.readToken(), '9|sesion-anterior');
    },
  );

  test('Un registro rechazado o sin conexión no crea una sesión', () async {
    for (final status in [401, 403, 503]) {
      final service = serviceWith(
        (_) async =>
            jsonResponse({'message': 'Registro no disponible'}, status),
      );
      await expectLater(register(service), throwsA(isA<ApiException>()));
      expect(await storage.readToken(), isNull);
    }
    final offline = serviceWith(
      (_) async => throw http.ClientException('offline'),
    );
    await expectLater(register(offline), throwsA(isA<ApiException>()));
    expect(await storage.readToken(), isNull);
  });

  test(
    'Login público conserva la contraseña y confirma el perfil con Bearer',
    () async {
      final paths = <String>[];
      final service = serviceWith((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/login') {
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], isNull);
          expect(jsonDecode(request.body), {
            'email': 'ana@example.test',
            'password': ' clave con espacios ',
          });
          return jsonResponse({'user': profile, 'token': '1|token-valido'});
        }
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer 1|token-valido');
        return jsonResponse({...profile, 'nombre': 'Ana actualizada'});
      });

      final user = await service.login(
        ' ana@example.test ',
        ' clave con espacios ',
      );
      expect(user.id, 1);
      expect(user.name, 'Ana actualizada');
      expect(user.email, 'ana@example.test');
      expect(paths, ['/api/login', '/api/me']);
      expect(await storage.readToken(), '1|token-valido');
      expect(await const FlutterSecureStorage().readAll(), {
        'agrofusion.auth_token': '1|token-valido',
      });
    },
  );

  for (final status in [401, 403, 422, 503]) {
    test('Un login con estado $status no guarda credenciales', () async {
      var calls = 0;
      final service = serviceWith((_) async {
        calls++;
        return jsonResponse({'message': 'Solicitud rechazada'}, status);
      });
      await expectLater(
        service.login('ana@example.test', 'clave'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
      expect(calls, 1);
      expect(await storage.readToken(), isNull);
    });
  }

  test('Una conexión fallida no produce una sesión local', () async {
    final service = serviceWith(
      (_) async => throw http.ClientException('offline'),
    );
    await expectLater(
      service.login('ana@example.test', 'clave'),
      throwsA(isA<ApiException>()),
    );
    expect(await storage.readToken(), isNull);
  });

  test('Rechaza tokens inválidos antes de consultar el perfil', () async {
    for (final token in [null, 7, '', 'token con espacios']) {
      var calls = 0;
      final service = serviceWith((_) async {
        calls++;
        return jsonResponse({'user': profile, 'token': token});
      });
      await expectLater(
        service.login('ana@example.test', 'clave'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
      expect(await storage.readToken(), isNull);
    }
  });

  test('Rechaza un login sin usuario aunque devuelva un token', () async {
    final service = serviceWith(
      (_) async => jsonResponse({'token': '1|token-valido'}),
    );
    await expectLater(
      service.login('ana@example.test', 'clave'),
      throwsA(isA<ApiException>()),
    );
    expect(await storage.readToken(), isNull);
  });

  for (final status in [401, 403, 503]) {
    test('Elimina el token recién guardado si me devuelve $status', () async {
      final service = serviceWith(
        (request) async => request.url.path == '/api/login'
            ? jsonResponse({'user': profile, 'token': '1|token-valido'})
            : jsonResponse({'message': 'Perfil no disponible'}, status),
      );
      await expectLater(
        service.login('ana@example.test', 'clave'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
      expect(await storage.readToken(), isNull);
    });
  }

  test(
    'Rechaza perfiles malformados, ajenos o no autorizados y limpia el token',
    () async {
      for (final response in [
        null,
        {'user': profile},
        {...profile, 'usuarioid': 0},
        {...profile, 'usuarioid': 2},
        {...profile, 'nombre': ''},
        {...profile, 'activo': false},
        {...profile, 'estado_cuenta': 'pendiente'},
      ]) {
        final service = serviceWith(
          (request) async => request.url.path == '/api/login'
              ? jsonResponse({'user': profile, 'token': '1|token-valido'})
              : jsonResponse(response),
        );
        await expectLater(
          service.login('ana@example.test', 'clave'),
          throwsA(isA<ApiException>()),
        );
        expect(await storage.readToken(), isNull);
      }
    },
  );

  test('Acepta una cuenta heredada activa con estado null', () async {
    final legacyProfile = {...profile, 'estado_cuenta': null};
    final service = serviceWith(
      (request) async => request.url.path == '/api/login'
          ? jsonResponse({'user': legacyProfile, 'token': '1|token-valido'})
          : jsonResponse(legacyProfile),
    );
    expect((await service.login('ana@example.test', 'clave')).id, 1);
  });

  test('Un fallo de almacenamiento impide completar el login', () async {
    var calls = 0;
    final service = serviceWith((_) async {
      calls++;
      return jsonResponse({'user': profile, 'token': '1|token-valido'});
    }, session: UnwritableSessionStorage());
    await expectLater(
      service.login('ana@example.test', 'clave'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('guardar la sesión'),
        ),
      ),
    );
    expect(calls, 1);
    expect(await storage.readToken(), isNull);
  });
}
