import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/failing_session_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const session = SessionStorage();

  ApiClient createApi(
    MockClient client, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api', timeout: timeout),
      sessionStorage: session,
      client: client,
    );
    addTearDown(api.close);
    return api;
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('Notifica la expiración solo para un 401 de la sesión actual', () async {
    await session.saveToken('1|token-actual');
    final api = createApi(MockClient((_) async => http.Response('', 401)));
    final events = <bool>[];
    final subscription = api.sessionExpired.listen(events.add);
    addTearDown(subscription.cancel);
    await expectLater(api.request('GET', 'me'), throwsA(isA<ApiException>()));
    expect(events, [true]);
    expect(await session.readToken(), isNull);
  });

  test(
    'Un 401 que no puede limpiar el token emite un estado de limpieza pendiente',
    () async {
      const token = '1|token-actual';
      final storage = FailingSessionStorage()..failClear = true;
      await storage.saveToken(token);
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((_) async => http.Response('', 401)),
      );
      addTearDown(api.close);
      final events = <bool>[];
      final subscription = api.sessionExpired.listen(events.add);
      addTearDown(subscription.cancel);
      await expectLater(api.request('GET', 'me'), throwsA(isA<ApiException>()));
      expect(events, [false]);
      expect(await storage.readToken(), token);
    },
  );

  test(
    'Un 403 de permisos o un 401 público no emiten expiración global',
    () async {
      await session.saveToken('1|token-actual');
      var status = 403;
      final api = createApi(MockClient((_) async => http.Response('', status)));
      final events = <bool>[];
      final subscription = api.sessionExpired.listen(events.add);
      addTearDown(subscription.cancel);
      await expectLater(
        api.request('GET', 'lotes'),
        throwsA(isA<ApiException>()),
      );
      status = 401;
      await expectLater(
        api.request('POST', 'login', authenticated: false),
        throwsA(isA<ApiException>()),
      );
      expect(events, isEmpty);
      expect(await session.readToken(), '1|token-actual');
    },
  );

  test(
    'Un Bearer explícito no altera una sesión más reciente ante un 401',
    () async {
      await session.saveToken('2|token-nuevo');
      final api = createApi(
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer 1|token-anterior');
          return http.Response('', 401);
        }),
      );
      await expectLater(
        api.request('POST', 'logout', bearerToken: '1|token-anterior'),
        throwsA(isA<ApiException>()),
      );
      expect(await session.readToken(), '2|token-nuevo');
    },
  );

  test('Envía JSON, Bearer y parámetros al servidor configurado', () async {
    await session.saveToken('1|token-de-prueba');
    final api = createApi(
      MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/lotes');
        expect(request.url.queryParameters, {'page': '2'});
        expect(request.headers['Accept'], 'application/json');
        expect(request.headers['Content-Type'], contains('application/json'));
        expect(request.headers['Authorization'], 'Bearer 1|token-de-prueba');
        expect(request.followRedirects, isFalse);
        expect(jsonDecode(request.body), {'nombre': 'Maíz'});
        return http.Response(
          '{"nombre":"Maíz"}',
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    expect(
      await api.request(
        'POST',
        'lotes',
        queryParameters: {'page': '2'},
        body: {'nombre': 'Maíz'},
      ),
      {'nombre': 'Maíz'},
    );
  });

  test(
    'Una petición pública no envía el token ni lo elimina por un 401',
    () async {
      await session.saveToken('1|token-de-prueba');
      final api = createApi(
        MockClient((request) async {
          expect(request.headers['Authorization'], isNull);
          return http.Response('{"message":"Credenciales incorrectas"}', 401);
        }),
      );

      await expectLater(
        api.request(
          'POST',
          'login',
          authenticated: false,
          bearerToken: 'token-que-no-debe-enviarse',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(await session.readToken(), '1|token-de-prueba');
    },
  );

  test(
    'Un 401 autenticado borra el token aunque el cuerpo no sea JSON',
    () async {
      await session.saveToken('1|token-de-prueba');
      final api = createApi(
        MockClient((_) async => http.Response('<html/>', 401)),
      );

      await expectLater(
        api.request('GET', 'me'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(await session.readToken(), isNull);
    },
  );

  test(
    'Un 401 de una sesión anterior no borra un token recién guardado',
    () async {
      await session.saveToken('1|token-anterior');
      final api = createApi(
        MockClient((_) async {
          await session.saveToken('2|token-nuevo');
          return http.Response('', 401);
        }),
      );

      await expectLater(
        api.request('GET', 'me'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(await session.readToken(), '2|token-nuevo');
    },
  );

  test('Un 422 conserva la sesión y expone los errores de validación', () async {
    await session.saveToken('1|token-de-prueba');
    final api = createApi(
      MockClient(
        (_) async => http.Response(
          '{"message":"Datos invalidos","errors":{"email":["Correo invalido"]}}',
          422,
        ),
      ),
    );

    await expectLater(
      api.request('POST', 'lotes', body: {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.validationErrors['email'], 'email', [
              'Correo invalido',
            ]),
      ),
    );
    expect(await session.readToken(), '1|token-de-prueba');
  });

  for (final status in [403, 500]) {
    test('Un $status no elimina la sesión', () async {
      await session.saveToken('1|token-de-prueba');
      final api = createApi(
        MockClient(
          (_) async => http.Response(
            '{"message":"Detalle interno del servidor"}',
            status,
          ),
        ),
      );

      await expectLater(
        api.request('GET', 'lotes'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', status)
              .having(
                (e) => e.message,
                'message',
                status == 500
                    ? 'El servidor no está disponible. Intenta más tarde.'
                    : 'Detalle interno del servidor',
              ),
        ),
      );
      expect(await session.readToken(), '1|token-de-prueba');
    });
  }

  test(
    'Un fallo de red no elimina la sesión ni reintenta la petición',
    () async {
      await session.saveToken('1|token-de-prueba');
      var attempts = 0;
      final api = createApi(
        MockClient((_) async {
          attempts++;
          throw http.ClientException('Sin conexión');
        }),
      );

      await expectLater(api.request('GET', 'me'), throwsA(isA<ApiException>()));
      expect(await session.readToken(), '1|token-de-prueba');
      expect(attempts, 1);
    },
  );

  test('El timeout devuelve un error y conserva la sesión', () async {
    await session.saveToken('1|token-de-prueba');
    final response = Completer<http.Response>();
    final api = createApi(
      MockClient((_) => response.future),
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      api.request('GET', 'me'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('tardó demasiado'),
        ),
      ),
    );
    expect(await session.readToken(), '1|token-de-prueba');
    response.complete(http.Response('{}', 200));
  });

  test('Un 204 no exige un cuerpo JSON', () async {
    final api = createApi(MockClient((_) async => http.Response('', 204)));
    expect(
      await api.request('DELETE', 'lotes/1', authenticated: false),
      isNull,
    );
  });

  test(
    'El multipart conserva el timeout sin repetir automáticamente la escritura',
    () async {
      await session.saveToken('1|token-perfil');
      var calls = 0;
      final pending = Completer<http.Response>();
      final api = createApi(
        MockClient((_) {
          calls++;
          return pending.future;
        }),
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        api.request(
          'POST',
          'me',
          fields: {'_method': 'PATCH'},
          files: [
            http.MultipartFile.fromBytes('imagen', [
              1,
              2,
            ], filename: 'foto.png'),
          ],
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'mensaje',
            contains('tardó demasiado'),
          ),
        ),
      );
      pending.complete(http.Response('{}', 200));
      expect(calls, 1);
      expect(await session.readToken(), '1|token-perfil');
    },
  );

  test(
    'Una respuesta exitosa con JSON inválido produce un error controlado',
    () async {
      final api = createApi(
        MockClient((_) async => http.Response('<html/>', 200)),
      );
      await expectLater(
        api.request('GET', 'test-api', authenticated: false),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('JSON inválida'),
          ),
        ),
      );
    },
  );
}
