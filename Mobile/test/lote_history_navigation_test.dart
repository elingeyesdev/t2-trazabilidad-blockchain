import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
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
  };
  const activity = {
    'actividadid': 11,
    'loteid': 7,
    'descripcion': 'Preparación del terreno',
    'fechafin': null,
  };

  http.Response json(Object? value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, Object?> page(
    List<Object?> rows, {
    int number = 1,
    int last = 1,
  }) => {
    'data': rows,
    'meta': {'current_page': number, 'last_page': last},
    'links': {'next': 'https://otro.test/no-seguir'},
  };

  Future<void> start(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(AgroFusionApp(apiClient: api));
    await tester.pumpAndSettle();
  }

  Future<void> push(WidgetTester tester, String route) async {
    unawaited(
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFromLote(WidgetTester tester) async {
    await push(tester, '${AppModule.lotes.route}/7');
    final access = find.text('Historial de actividades');
    await tester.ensureVisible(access);
    await tester.tap(access);
    await tester.pumpAndSettle();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|historial');
  });

  for (final back in ['botón', 'flecha', 'Android']) {
    testWidgets('Abre el historial desde el lote y vuelve con $back', (
      tester,
    ) async {
      var detailCalls = 0;
      var historyCalls = 0;
      await start(tester, (request) async {
        expect(request.headers['Authorization'], 'Bearer 1|historial');
        if (request.url.path == '/api/me') return json(profile);
        if (request.url.path == '/api/lotes/7') {
          detailCalls++;
          return json({'data': lot});
        }
        expect(request.url.path, '/api/lotes/7/actividades');
        expect(request.url.queryParameters, {'page': '1'});
        historyCalls++;
        return json(page([activity]));
      });
      await openFromLote(tester);
      expect(find.text('Maíz del Norte'), findsOneWidget);
      expect(find.text('Preparación del terreno'), findsOneWidget);
      expect(find.text('Información del lote'), findsNothing);
      expect(historyCalls, 1);
      switch (back) {
        case 'botón':
          await tester.tap(
            find.widgetWithText(OutlinedButton, 'Volver al lote'),
          );
        case 'flecha':
          await tester.tap(find.byTooltip('Volver al lote'));
        default:
          await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.text('Información del lote'), findsOneWidget);
      expect(find.text('Preparación del terreno'), findsNothing);
      expect(detailCalls, 1);
    });
  }

  testWidgets('Recorre las páginas del historial usando la API configurada', (
    tester,
  ) async {
    final pages = <int>[];
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      if (request.url.path == '/api/lotes/7') return json({'data': lot});
      expect(request.url.host, 'example.test');
      expect(request.url.path, '/api/lotes/7/actividades');
      final number = int.parse(request.url.queryParameters['page']!);
      pages.add(number);
      return json(
        page(
          [
            number == 1
                ? activity
                : {
                    ...activity,
                    'actividadid': 12,
                    'descripcion': 'Riego del lote',
                  },
          ],
          number: number,
          last: 2,
        ),
      );
    });
    await openFromLote(tester);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Riego del lote'), findsOneWidget);
    expect(find.text('Preparación del terreno'), findsNothing);
    await tester.tap(find.text('Anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Preparación del terreno'), findsOneWidget);
    expect(pages, [1, 2, 1]);
  });

  testWidgets(
    'El acceso directo exige permiso antes de consultar el historial',
    (tester) async {
      var calls = 0;
      await start(tester, (request) async {
        if (request.url.path == '/api/me') {
          return json({...profile, 'permissions': []});
        }
        calls++;
        return json(page([activity]));
      });
      await push(tester, '/modules/lotes/7/historial');
      expect(find.text('Acceso no autorizado'), findsOneWidget);
      expect(calls, 0);
    },
  );

  for (final status in [401, 403, 404]) {
    testWidgets('El historial maneja una respuesta $status sin mostrar datos', (
      tester,
    ) async {
      await start(tester, (request) async {
        if (request.url.path == '/api/me') return json(profile);
        return json({}, status);
      });
      await push(tester, '/modules/lotes/7/historial');
      if (status == 401) {
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(await storage.readToken(), isNull);
      } else {
        expect(
          find.text(
            status == 403
                ? 'Acceso no autorizado'
                : 'El lote ya no está disponible',
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Preparación del terreno'), findsNothing);
    });
  }

  testWidgets('Un fallo de conexión permite reintentar en el mismo lote', (
    tester,
  ) async {
    var calls = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      if (request.url.path == '/api/lotes/7') return json({'data': lot});
      return ++calls == 1 ? json({}, 503) : json(page([activity]));
    });
    await openFromLote(tester);
    expect(find.text('No pudimos cargar la información'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Preparación del terreno'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('Retirar el permiso oculta un historial que estaba abierto', (
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
      return json(page([activity]));
    });
    await push(tester, '/modules/lotes/7/historial');
    expect(find.text('Preparación del terreno'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Acceso no autorizado'), findsOneWidget);
    expect(find.text('Preparación del terreno'), findsNothing);
  });

  testWidgets(
    'El acceso y el historial admiten letras grandes en pantalla chica',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await start(tester, (request) async {
        if (request.url.path == '/api/me') return json(profile);
        if (request.url.path == '/api/lotes/7') return json({'data': lot});
        return json(page([activity]));
      });
      await openFromLote(tester);
      await tester.scrollUntilVisible(
        find.text('Preparación del terreno'),
        200,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Volver al lote'));
      await tester.pumpAndSettle();
      expect(find.text('Información del lote'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
