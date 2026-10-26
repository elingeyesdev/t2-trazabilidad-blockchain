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
