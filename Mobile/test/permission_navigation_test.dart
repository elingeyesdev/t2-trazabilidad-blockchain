import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/navigation/app_routes.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/screens/home/home_screen.dart';
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
    'permissions': ['pedidos.view'],
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
    await storage.saveToken('1|modulos');
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

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final permissions in <Set<String>>[
    {},
    {'lotes.view'},
    {'inventario.view', 'pedidos.view'},
    {'usuarios.view'},
    {'usuarios.admin'},
    {for (final module in AppModule.values) module.permission},
  ]) {
    testWidgets('El menú coincide con los permisos efectivos $permissions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            user: AuthUser(
              id: 1,
              name: 'Ana',
              email: 'ana@example.test',
              roles: const ['admin', 'agricultor'],
              permissions: permissions,
            ),
            onLogout: () {},
          ),
        ),
      );
      for (final module in AppModule.values) {
        expect(
          find.text(module.label),
          permissions.contains(module.permission)
              ? findsOneWidget
              : findsNothing,
        );
      }
      expect(find.text('Mi perfil'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'El acceso directo sin permiso se bloquea antes de consultar el módulo',
    (tester) async {
      var calls = 0;
      await start(tester, (_) async {
        calls++;
        return json({
          ...profile,
          'roles': [
            {'name': 'admin'},
          ],
          'permissions': [],
        });
      });
      for (final module in AppModule.values) {
        await push(tester, module.route);
        expect(find.text('Acceso no autorizado'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(calls, 1);
    },
  );

  testWidgets(
    'Un permiso directo sin roles abre la consulta real desde el menú',
    (tester) async {
      await start(
        tester,
        (request) async => request.url.path == '/api/me'
            ? json(profile)
            : json([
                {
                  'pedidoid': 9,
                  'numero_solicitud': 'SOL-009',
                  'nombre_planta': 'Planta Sur',
                  'estado': 'pendiente',
                },
              ]),
      );
      await tester.ensureVisible(find.text('Pedidos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedidos'));
      await tester.pumpAndSettle();
      expect(find.text('SOL-009'), findsOneWidget);
      expect(find.text('Planta: Planta Sur'), findsOneWidget);
      expect(find.text('Estado: pendiente'), findsOneWidget);
      expect(find.text('Consulta de registros'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Hola, Ana'), findsOneWidget);
    },
  );

  testWidgets(
    'La consulta vacía tiene un estado explícito y permite actualizar',
    (tester) async {
      var calls = 0;
      await start(tester, (request) async {
        if (request.url.path == '/api/me') return json(profile);
        calls++;
        return json([]);
      });
      await push(tester, AppModule.pedidos.route);
      expect(find.text('No hay registros disponibles.'), findsOneWidget);
      await tester.tap(find.byTooltip('Actualizar lista'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );

  testWidgets(
    'Un 403 del servidor permite volver al inicio sin cerrar la sesión',
    (tester) async {
      await start(
        tester,
        (request) async =>
            request.url.path == '/api/me' ? json(profile) : json({}, 403),
      );
      await push(tester, AppModule.pedidos.route);
      expect(find.text('Acceso no autorizado'), findsOneWidget);
      expect(await storage.readToken(), '1|modulos');
      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Ana'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    },
  );

  testWidgets('Un 401 del módulo retira los datos y bloquea volver a ellos', (
    tester,
  ) async {
    await start(
      tester,
      (request) async =>
          request.url.path == '/api/me' ? json(profile) : json({}, 401),
    );
    await push(tester, AppModule.pedidos.route);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(await storage.readToken(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Hola, Ana'), findsNothing);
  });

  testWidgets('Un fallo de red ofrece reintento y conserva la navegación', (
    tester,
  ) async {
    var attempts = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') return json(profile);
      if (++attempts == 1) throw http.ClientException('offline');
      return json([
        {'pedidoid': 1, 'numero_solicitud': 'Recuperado'},
      ]);
    });
    await push(tester, AppModule.pedidos.route);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Recuperado'), findsOneWidget);
    expect(await storage.readToken(), '1|modulos');
  });

  testWidgets('La consulta pagina sin seguir una URL externa de la respuesta', (
    tester,
  ) async {
    await start(tester, (request) async {
      if (request.url.path == '/api/me') {
        return json({
          ...profile,
          'permissions': ['rutas_multi.view'],
        });
      }
      final page = int.parse(request.url.queryParameters['page']!);
      expect(request.url.path, '/api/rutas-multi');
      return json({
        'data': [
          {'rutamultientregaid': page, 'nombre': 'Ruta $page'},
        ],
        'current_page': page,
        'last_page': 2,
        'next_page_url': 'https://externo.test',
      });
    });
    await push(tester, AppModule.rutas.route);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Ruta 2'), findsOneWidget);
    expect(find.text('Página 2 de 2'), findsOneWidget);
    await tester.tap(find.text('Anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Ruta 1'), findsOneWidget);
  });

  testWidgets(
    'Al retirar un permiso el destino abierto deja de mostrar sus datos',
    (tester) async {
      var meCalls = 0;
      var moduleCalls = 0;
      await start(tester, (request) async {
        if (request.url.path == '/api/me') {
          return json({
            ...profile,
            'permissions': ++meCalls == 1 ? ['pedidos.view'] : [],
          });
        }
        moduleCalls++;
        return json([
          {'pedidoid': 1, 'numero_solicitud': 'Dato protegido'},
        ]);
      });
      await push(tester, AppModule.pedidos.route);
      expect(find.text('Dato protegido'), findsOneWidget);
      await push(tester, AppRoutes.profile);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Acceso no autorizado'), findsOneWidget);
      expect(find.text('Dato protegido'), findsNothing);
      expect(moduleCalls, 1);
      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();
      expect(find.text('Pedidos'), findsNothing);
      expect(find.text('Mi perfil'), findsOneWidget);
    },
  );
}
