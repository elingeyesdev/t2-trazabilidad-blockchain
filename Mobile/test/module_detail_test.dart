import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();
  const profile = {
    'usuarioid': 1,
    'nombre': 'Ana',
    'email': 'ana@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'permissions': ['lotes.view'],
  };
  const lot = {
    'loteid': 7,
    'nombre': 'Maíz del Norte',
    'ubicacion': 'Sector alto',
    'superficie': 1.25,
    'fechasiembra': '2026-10-20T00:00:00.000000Z',
    'codigo_trazabilidad': 'AF-007',
  };
  const activity = {
    'actividadid': 11,
    'descripcion': 'Preparación del terreno',
    'fecha_planificada': '2026-10-29T00:00:00.000000Z',
    'fechainicio': null,
    'fechafin': null,
    'observaciones': 'Revisar los surcos del sector norte.',
  };

  http.Response json(Object? value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  ApiClient client(Future<http.Response> Function(http.Request) handler) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    return api;
  }

  Future<void> start(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    await tester.pumpWidget(AgroFusionApp(apiClient: client(handler)));
    await tester.pumpAndSettle();
  }

  Future<void> push(WidgetTester tester, String route) async {
    unawaited(
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|detalle');
  });

  test(
    'El servicio valida permisos e identificación antes de entregar un detalle',
    () async {
      var calls = 0;
      Object? response = lot;
      final service = ModuleService(
        client((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/lotes/7');
          expect(request.headers['Authorization'], 'Bearer 1|detalle');
          return json(response);
        }),
      );
      const allowed = AuthUser(
        id: 1,
        name: 'Ana',
        email: 'ana@example.test',
        permissions: {'lotes.view'},
      );
      const denied = AuthUser(
        id: 1,
        name: 'Ana',
        email: 'ana@example.test',
        roles: ['admin'],
      );
      await expectLater(
        service.loadDetail(AppModule.lotes, denied, 7),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
      await expectLater(
        service.loadDetail(AppModule.lotes, allowed, 0),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        service.loadDetail(AppModule.pedidos, allowed, 7),
        throwsArgumentError,
      );
      expect(calls, 0);
      final record = await service.loadDetail(AppModule.lotes, allowed, 7);
      expect(record.id, 7);
      expect(record.details['Código de trazabilidad'], 'AF-007');
      for (final invalid in [
        null,
        [],
        {...lot, 'loteid': 8},
        {...lot, 'loteid': '7'},
        {...lot, 'nombre': {}},
      ]) {
        response = invalid;
        await expectLater(
          service.loadDetail(AppModule.lotes, allowed, 7),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  for (final module in [AppModule.lotes, AppModule.actividades]) {
    testWidgets(
      'Abre el registro seleccionado de ${module.label} y consulta sus datos actuales',
      (tester) async {
        final row = module == AppModule.lotes ? lot : activity;
        final title = row[module.titleField]! as String;
        final id = row[module.idField]! as int;
        var detailCalls = 0;
        await start(tester, (request) async {
          if (request.url.path == '/api/me') return json(profile);
          if (request.url.path == '/api/${module.endpoint}') {
            return json([
              row,
              {
                ...row,
                module.idField: id + 1,
                module.titleField!: 'Otro registro',
              },
            ]);
          }
          expect(request.url.path, '/api/${module.endpoint}/$id');
          detailCalls++;
          return json({
            ...row,
            module.titleField!: '$title actualizado',
            'passwordhash': 'privado',
          });
        });
        await push(tester, module.route);
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(
          find.text(
            module == AppModule.lotes
                ? 'Detalle del lote'
                : 'Detalle de actividad',
          ),
          findsOneWidget,
        );
        expect(find.text('$title actualizado'), findsOneWidget);
        expect(find.text('Otro registro'), findsNothing);
        expect(find.text('privado'), findsNothing);
        expect(
          find.text(
            module == AppModule.lotes ? '1,25 hectáreas' : '29/10/2026',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.text(
            module == AppModule.lotes
                ? 'AF-007'
                : 'Revisar los surcos del sector norte.',
          ),
        );
        await tester.pumpAndSettle();
        expect(detailCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('El detalle muestra carga mientras espera a Laravel', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      if (request.url.path == '/api/lotes') return json([lot]);
      return pending.future;
    });
    await push(tester, AppModule.lotes.route);
    await tester.tap(find.text('Maíz del Norte'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Cargando detalle...'), findsOneWidget);
    pending.complete(json(lot));
    await tester.pumpAndSettle();
    expect(find.text('Información del lote'), findsOneWidget);
  });

  testWidgets('Permite reintentar una consulta del detalle que falló', (
    tester,
  ) async {
    var calls = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      if (++calls == 1) throw http.ClientException('offline');
      return json(lot);
    });
    await push(tester, '${AppModule.lotes.route}/7');
    expect(find.text('No pudimos cargar la información'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Maíz del Norte'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('Actualizar detalle muestra la información nueva del servidor', (
    tester,
  ) async {
    var calls = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      return json({
        ...lot,
        'ubicacion': ++calls == 1 ? 'Sector alto' : 'Sector actualizado',
      });
    });
    await push(tester, '${AppModule.lotes.route}/7');
    expect(find.text('Sector alto'), findsOneWidget);
    await tester.tap(find.byTooltip('Actualizar detalle'));
    await tester.pumpAndSettle();
    expect(find.text('Sector actualizado'), findsOneWidget);
    expect(find.text('Sector alto'), findsNothing);
    expect(calls, 2);
  });

  testWidgets('Un registro eliminado ofrece volver a la lista', (tester) async {
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      if (request.url.path == '/api/lotes') return json([lot]);
      return json({}, 404);
    });
    await push(tester, AppModule.lotes.route);
    await tester.tap(find.text('Maíz del Norte'));
    await tester.pumpAndSettle();
    expect(find.text('El registro ya no está disponible'), findsOneWidget);
    await tester.tap(find.text('Volver a la lista'));
    await tester.pumpAndSettle();
    expect(find.text('Lotes'), findsOneWidget);
    expect(find.text('Maíz del Norte'), findsOneWidget);
  });

  for (final status in [401, 403]) {
    testWidgets('El detalle protege los datos ante una respuesta $status', (
      tester,
    ) async {
      await start(
        tester,
        (request) async =>
            request.url.path == '/api/me' ? json(profile) : json({}, status),
      );
      await push(tester, '${AppModule.lotes.route}/7');
      if (status == 401) {
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(await storage.readToken(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      } else {
        expect(find.text('Acceso no autorizado'), findsOneWidget);
        expect(await storage.readToken(), '1|detalle');
      }
      expect(find.text('Información del lote'), findsNothing);
    });
  }

  testWidgets('Una ruta directa al detalle también exige permiso', (
    tester,
  ) async {
    var calls = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') {
        return json({...profile, 'permissions': []});
      }
      calls++;
      return json(lot);
    });
    await push(tester, '${AppModule.lotes.route}/7');
    expect(find.text('Acceso no autorizado'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('Retirar el permiso oculta un detalle que estaba abierto', (
    tester,
  ) async {
    var meCalls = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') {
        return json({
          ...profile,
          'permissions': ++meCalls == 1 ? ['lotes.view'] : [],
        });
      }
      return json(lot);
    });
    await push(tester, '${AppModule.lotes.route}/7');
    expect(find.text('Información del lote'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Acceso no autorizado'), findsOneWidget);
    expect(find.text('Maíz del Norte'), findsNothing);
  });

  testWidgets('El detalle se desplaza con letras grandes y en horizontal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(
      tester,
      (request) async =>
          json(request.url.path == '/api/me' ? profile : activity),
    );
    await push(tester, '${AppModule.actividades.route}/11');
    await tester.ensureVisible(
      find.text('Revisar los surcos del sector norte.'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(812, 375);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('Revisar los surcos del sector norte.'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
