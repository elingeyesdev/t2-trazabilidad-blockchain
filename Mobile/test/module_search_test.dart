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
  const lots = [
    {'loteid': 7, 'nombre': 'Maíz del Norte', 'ubicacion': 'Sector alto'},
    {'loteid': 8, 'nombre': 'Papa del Sur', 'ubicacion': 'Sector bajo'},
  ];

  http.Response json(Object? value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

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

  Future<void> push(WidgetTester tester, AppModule module) async {
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed(module.route),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(
    WidgetTester tester,
    AppModule module,
    String query,
  ) async {
    await tester.tap(find.byTooltip('Buscar ${module.label.toLowerCase()}'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|buscar');
  });

  for (final module in [AppModule.lotes, AppModule.actividades]) {
    testWidgets(
      'Busca ${module.label}, limpia y vuelve con el botón de Android',
      (tester) async {
        final firstTitle = module == AppModule.lotes
            ? 'Maíz del Norte'
            : 'Preparación del terreno';
        final secondTitle = module == AppModule.lotes
            ? 'Papa del Sur'
            : 'Riego de la parcela';
        var calls = 0;
        await start(tester, (request) async {
          if (request.url.path == '/api/me') return json(profile);
          expect(request.url.path, '/api/${module.endpoint}');
          calls++;
          return json([
            {module.idField: 7, module.titleField!: firstTitle},
            {module.idField: 8, module.titleField!: secondTitle},
          ]);
        });
        await push(tester, module);
        await search(
          tester,
          module,
          module == AppModule.lotes ? '  NORTE   MAIZ  ' : 'PREPARACION',
        );
        expect(find.text(firstTitle), findsOneWidget);
        expect(find.text(secondTitle), findsNothing);

        await tester.enterText(find.byType(TextField), 'registro inexistente');
        await tester.pumpAndSettle();
        expect(find.text('No encontramos coincidencias'), findsOneWidget);
        await tester.tap(find.byTooltip('Limpiar búsqueda'));
        await tester.pumpAndSettle();
        expect(find.text(firstTitle), findsOneWidget);
        expect(find.text(secondTitle), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text(module.label), findsOneWidget);
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'La búsqueda incluye los datos visibles y se conserva al actualizar',
    (tester) async {
      var calls = 0;
      await start(tester, (request) async {
        if (request.url.path == '/api/me') return json(profile);
        calls++;
        return json(lots);
      });
      await push(tester, AppModule.lotes);
      await search(tester, AppModule.lotes, 'ALTO');
      expect(find.text('Maíz del Norte'), findsOneWidget);
      expect(find.text('Papa del Sur'), findsNothing);
      await tester.tap(find.byTooltip('Actualizar lista'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'ALTO',
      );
      expect(find.text('Papa del Sur'), findsNothing);
      expect(calls, 2);
      await tester.tap(find.byTooltip('Cerrar búsqueda'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Papa del Sur'), findsOneWidget);
    },
  );

  testWidgets('Distingue una lista vacía de una búsqueda sin coincidencias', (
    tester,
  ) async {
    await start(
      tester,
      (request) async => json(request.url.path == '/api/me' ? profile : []),
    );
    await push(tester, AppModule.lotes);
    await search(tester, AppModule.lotes, 'maiz');
    expect(find.text('Todavía no hay lotes'), findsOneWidget);
    expect(find.text('No encontramos coincidencias'), findsNothing);
  });

  testWidgets('Un 403 al actualizar retira los resultados de la búsqueda', (
    tester,
  ) async {
    var calls = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      return ++calls == 1 ? json(lots) : json({}, 403);
    });
    await push(tester, AppModule.lotes);
    await search(tester, AppModule.lotes, 'maiz');
    await tester.tap(find.byTooltip('Actualizar lista'));
    await tester.pumpAndSettle();
    expect(find.text('Acceso no autorizado'), findsOneWidget);
    expect(find.text('Maíz del Norte'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(await storage.readToken(), '1|buscar');
  });

  testWidgets('Un 401 al actualizar la búsqueda bloquea volver a los datos', (
    tester,
  ) async {
    var calls = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      return ++calls == 1 ? json(lots) : json({}, 401);
    });
    await push(tester, AppModule.lotes);
    await search(tester, AppModule.lotes, 'maiz');
    await tester.tap(find.byTooltip('Actualizar lista'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(await storage.readToken(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Maíz del Norte'), findsNothing);
  });

  testWidgets(
    'Al retirar el permiso una búsqueda abierta deja de mostrar datos',
    (tester) async {
      var meCalls = 0;
      await start(tester, (request) async {
        if (request.url.path == '/api/me') {
          return json({
            ...profile,
            'permissions': ++meCalls == 1 ? ['lotes.view'] : [],
          });
        }
        return json(lots);
      });
      await push(tester, AppModule.lotes);
      await search(tester, AppModule.lotes, 'maiz');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Acceso no autorizado'), findsOneWidget);
      expect(find.text('Maíz del Norte'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('La búsqueda no se añade a otros módulos', (tester) async {
    await start(
      tester,
      (request) async => request.url.path == '/api/me'
          ? json({
              ...profile,
              'permissions': ['pedidos.view'],
            })
          : json([
              {'pedidoid': 7, 'numero_solicitud': 'SOL-007'},
            ]),
    );
    await push(tester, AppModule.pedidos);
    expect(find.text('SOL-007'), findsOneWidget);
    expect(find.byTooltip('Buscar pedidos'), findsNothing);
  });

  testWidgets(
    'Permite buscar con texto ampliado y teclado en pantallas pequeñas',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await start(
        tester,
        (request) async => json(request.url.path == '/api/me' ? profile : lots),
      );
      await push(tester, AppModule.lotes);
      await search(tester, AppModule.lotes, 'maiz');
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'no existe');
      await tester.pumpAndSettle();
      expect(find.text('No encontramos coincidencias'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(812, 375);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
