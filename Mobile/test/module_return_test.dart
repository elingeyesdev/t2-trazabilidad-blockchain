import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
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
  };

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

  Future<void> push(WidgetTester tester, String route) async {
    unawaited(
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|volver');
  });

  for (final module in [AppModule.lotes, AppModule.actividades]) {
    for (final action in ['botón', 'flecha', 'Android']) {
      testWidgets(
        'Regresa a ${module.label} con $action y conserva búsqueda y posición',
        (tester) async {
          final prefix = module == AppModule.lotes ? 'Maíz' : 'Riego';
          final query = module == AppModule.lotes ? 'maiz' : 'riego';
          final rows = List.generate(
            28,
            (index) => {
              module.idField: index + 1,
              module.titleField!: '$prefix parcela ${index + 1}',
            },
          );
          var listCalls = 0;
          await start(tester, (request) async {
            if (request.url.path == '/api/me') return json(profile);
            if (request.url.path == '/api/${module.endpoint}') {
              listCalls++;
              return json(rows);
            }
            final id = int.parse(request.url.pathSegments.last);
            return json(rows[id - 1]);
          });
          await push(tester, module.route);
          await tester.tap(
            find.byTooltip('Buscar ${module.label.toLowerCase()}'),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), query);
          FocusManager.instance.primaryFocus?.unfocus();
          tester.testTextInput.hide();
          await tester.pumpAndSettle();

          final scrollable = find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          );
          final selected = '$prefix parcela 17';
          await tester.scrollUntilVisible(
            find.text(selected),
            400,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          final offset = tester
              .state<ScrollableState>(scrollable)
              .position
              .pixels;
          expect(offset, greaterThan(0));
          await tester.tap(find.text(selected));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Información ${module == AppModule.lotes ? 'del lote' : 'de la actividad'}',
            ),
            findsOneWidget,
          );

          switch (action) {
            case 'botón':
              await tester.tap(find.text('Volver a la lista'));
            case 'flecha':
              await tester.tap(find.byTooltip('Volver a la lista'));
            case 'Android':
              await tester.binding.handlePopRoute();
          }
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            query,
          );
          expect(
            tester.state<ScrollableState>(scrollable).position.pixels,
            closeTo(offset, .5),
          );
          expect(find.text(selected).hitTestable(), findsOneWidget);
          expect(listCalls, 1);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('El regreso conserva la página consultada y su búsqueda', (
    tester,
  ) async {
    final pages = <int>[];
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      if (request.url.path == '/api/lotes') {
        final page = int.parse(request.url.queryParameters['page']!);
        pages.add(page);
        return json({
          'data': [
            {...lot, 'loteid': page * 100 + 7, 'nombre': 'Maíz página $page'},
          ],
          'current_page': page,
          'last_page': 3,
        });
      }
      return json({...lot, 'loteid': 207, 'nombre': 'Maíz página 2'});
    });
    await push(tester, AppModule.lotes.route);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buscar lotes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'maiz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maíz página 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver a la lista'));
    await tester.pumpAndSettle();
    expect(find.text('Página 2 de 3'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'maiz',
    );
    expect(pages, [1, 2]);
  });

  testWidgets(
    'Si no había una lista abierta, volver la abre sin dejar el detalle debajo',
    (tester) async {
      await start(tester, (request) async {
        if (request.url.path == '/api/me') return json(profile);
        return json(request.url.path == '/api/lotes' ? [lot] : lot);
      });
      await push(tester, '${AppModule.lotes.route}/7');
      await tester.tap(find.text('Volver a la lista'));
      await tester.pumpAndSettle();
      expect(find.text('Lotes'), findsOneWidget);
      expect(find.text('Ver detalle'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Hola, Ana'), findsOneWidget);
      expect(find.text('Detalle del lote'), findsNothing);
    },
  );

  testWidgets('El botón permite regresar después de un error de conexión', (
    tester,
  ) async {
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      if (request.url.path == '/api/lotes') return json([lot]);
      throw http.ClientException('offline');
    });
    await push(tester, AppModule.lotes.route);
    await tester.tap(find.text('Maíz del Norte'));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar la información'), findsOneWidget);
    await tester.tap(find.text('Volver a la lista'));
    await tester.pumpAndSettle();
    expect(find.text('Lotes'), findsOneWidget);
    expect(find.text('Maíz del Norte'), findsOneWidget);
  });

  testWidgets('Permite volver mientras el detalle todavía está cargando', (
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
    await tester.tap(find.text('Volver a la lista'));
    pending.complete(json(lot));
    await tester.pumpAndSettle();
    expect(find.text('Lotes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Volver después de perder el permiso no recupera los datos anteriores',
    (tester) async {
      var meCalls = 0;
      await start(tester, (request) async {
        if (request.url.path == '/api/me') {
          return json({
            ...profile,
            'permissions': ++meCalls == 1 ? ['lotes.view'] : [],
          });
        }
        return json(request.url.path == '/api/lotes' ? [lot] : lot);
      });
      await push(tester, AppModule.lotes.route);
      await tester.tap(find.text('Maíz del Norte'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Acceso no autorizado'), findsOneWidget);
      expect(find.text('Maíz del Norte'), findsNothing);
    },
  );

  testWidgets(
    'El botón para volver sigue visible con letras grandes y en horizontal',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await start(tester, (request) async {
        if (request.url.path == '/api/me') return json(profile);
        return json(request.url.path == '/api/lotes' ? [lot] : lot);
      });
      await push(tester, AppModule.lotes.route);
      await tester.ensureVisible(find.text('Maíz del Norte'));
      await tester.tap(find.text('Maíz del Norte'));
      await tester.pumpAndSettle();
      expect(find.text('Volver a la lista').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(812, 375);
      await tester.pumpAndSettle();
      expect(find.text('Volver a la lista').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Volver a la lista'));
      await tester.pumpAndSettle();
      expect(find.text('Lotes'), findsOneWidget);
    },
  );
}
