import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();
  const deniedUser = AuthUser(
    id: 1,
    name: 'Ana',
    email: 'ana@example.test',
    roles: ['admin'],
  );

  AuthUser allowedUser(AppModule module) => AuthUser(
    id: 1,
    name: 'Ana',
    email: 'ana@example.test',
    permissions: {module.permission},
  );

  ModuleService service(Future<http.Response> Function(http.Request) handler) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    return ModuleService(api);
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|modulos');
  });

  test(
    'Sin el permiso concreto no envía HTTP, incluso con rol admin',
    () async {
      var calls = 0;
      final modules = service((_) async {
        calls++;
        return http.Response('[]', 200);
      });
      for (final module in AppModule.values) {
        await expectLater(
          modules.load(module, deniedUser),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 403),
          ),
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'Cada destino consulta su endpoint y solo interpreta sus campos declarados',
    () async {
      for (final module in AppModule.values) {
        final modules = service((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/${module.endpoint}');
          expect(request.url.queryParameters, {'page': '1'});
          expect(request.headers['Authorization'], 'Bearer 1|modulos');
          return http.Response(
            jsonEncode([
              {
                module.idField: 7,
                if (module.titleField != null)
                  module.titleField!: 'Registro real',
                for (final field in module.fields.keys)
                  field: switch (field) {
                    'superficie' => 2.5,
                    'fecha_planificada' || 'fechainicio' => '2026-10-29',
                    _ => 'Dato de Laravel',
                  },
                'passwordhash': 'nunca mostrar',
                'metadata': {'privado': true},
              },
            ]),
            200,
          );
        });
        final page = await modules.load(module, allowedUser(module));
        expect(
          page.records.single.title,
          module.titleField == null ? '${module.label} #7' : 'Registro real',
        );
        expect(page.records.single.details['Identificador'], '7');
        expect(
          page.records.single.details.values,
          isNot(contains('nunca mostrar')),
        );
        expect(page.currentPage, 1);
        expect(page.lastPage, 1);
      }
    },
  );

  test(
    'La paginación usa el endpoint configurado e ignora URLs recibidas',
    () async {
      final modules = service((request) async {
        expect(request.url.host, 'example.test');
        expect(request.url.queryParameters, {'page': '2'});
        return http.Response(
          jsonEncode({
            'data': [
              {'rutamultientregaid': 4, 'nombre': 'Ruta 4'},
            ],
            'current_page': 2,
            'last_page': 3,
            'next_page_url': 'https://otro.test/robar',
          }),
          200,
        );
      });
      final page = await modules.load(
        AppModule.rutas,
        allowedUser(AppModule.rutas),
        page: 2,
      );
      expect(page.currentPage, 2);
      expect(page.lastPage, 3);
      expect(page.records.single.title, 'Ruta 4');
    },
  );

  test('Rechaza registros y metadatos de paginación inválidos', () async {
    for (final payload in [
      null,
      {},
      {'data': [], 'current_page': 0, 'last_page': 1},
      {'data': [], 'current_page': 2, 'last_page': 1},
      ['texto'],
      [
        {'loteid': '7'},
      ],
      [
        {'loteid': 7, 'nombre': {}},
      ],
    ]) {
      final modules = service(
        (_) async => http.Response(jsonEncode(payload), 200),
      );
      await expectLater(
        modules.load(AppModule.lotes, allowedUser(AppModule.lotes)),
        throwsA(isA<ApiException>()),
      );
    }
  });

  test('Un 403 no elimina el token y se entrega a la pantalla', () async {
    final modules = service((_) async => http.Response('{}', 403));
    await expectLater(
      modules.load(AppModule.pedidos, allowedUser(AppModule.pedidos)),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
    expect(await storage.readToken(), '1|modulos');
  });

  test('Lee las listas y los detalles del formato actual de Laravel', () async {
    for (final module in [AppModule.lotes, AppModule.actividades]) {
      final row = {module.idField: 7, module.titleField!: 'Registro de campo'};
      final modules = service(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/7')
                ? {'data': row}
                : {
                    'data': [row],
                    'meta': {'current_page': 2, 'last_page': 3},
                    'links': {'next': 'https://otro.test/ignorar'},
                  },
          ),
          200,
        ),
      );
      final user = allowedUser(module);
      final list = await modules.load(module, user, page: 2);
      expect(list.currentPage, 2);
      expect(list.lastPage, 3);
      expect(list.records.single.title, 'Registro de campo');
      final detail = await modules.loadDetail(module, user, 7);
      expect(detail.id, 7);
      expect(detail.title, list.records.single.title);
    }
  });

  test('Rechaza envoltorios y metadatos incompletos de Laravel', () async {
    for (final payload in [
      {'data': [], 'meta': null},
      {
        'data': [],
        'meta': {'current_page': 0, 'last_page': 1},
      },
      {
        'data': [],
        'meta': {'current_page': 2, 'last_page': 1},
      },
      {
        'data': [],
        'meta': {'current_page': 1},
      },
      {
        'data': [],
        'meta': {'current_page': '1', 'last_page': 1},
      },
    ]) {
      final modules = service(
        (_) async => http.Response(jsonEncode(payload), 200),
      );
      await expectLater(
        modules.load(AppModule.lotes, allowedUser(AppModule.lotes)),
        throwsA(isA<ApiException>()),
      );
    }
    for (final value in [
      null,
      [],
      {'loteid': 8},
    ]) {
      final modules = service(
        (_) async => http.Response(jsonEncode({'data': value}), 200),
      );
      await expectLater(
        modules.loadDetail(AppModule.lotes, allowedUser(AppModule.lotes), 7),
        throwsA(isA<ApiException>()),
      );
    }
  });

  test(
    'El historial valida permiso, lote y página antes de consultar',
    () async {
      var calls = 0;
      final modules = service((_) async {
        calls++;
        return http.Response('[]', 200);
      });
      final user = allowedUser(AppModule.lotes);
      await expectLater(
        modules.loadLoteActivities(deniedUser, 7),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            403,
          ),
        ),
      );
      await expectLater(
        modules.loadLoteActivities(user, 0),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        modules.loadLoteActivities(user, 7, page: 0),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 0);
    },
  );

  test('No entrega actividades de otro lote ni una página distinta', () async {
    for (final payload in [
      {
        'data': [
          {'actividadid': 11, 'loteid': 8},
        ],
        'meta': {'current_page': 1, 'last_page': 1},
      },
      {
        'data': [
          {'actividadid': 11},
        ],
        'meta': {'current_page': 1, 'last_page': 1},
      },
      {
        'data': [
          {'actividadid': 11, 'loteid': 7},
        ],
        'meta': {'current_page': 2, 'last_page': 2},
      },
    ]) {
      final modules = service(
        (_) async => http.Response(jsonEncode(payload), 200),
      );
      await expectLater(
        modules.loadLoteActivities(allowedUser(AppModule.lotes), 7),
        throwsA(isA<ApiException>()),
      );
    }
  });
}
