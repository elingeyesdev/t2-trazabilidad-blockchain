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
import 'package:agrofusion_mobile/theme/app_theme.dart';
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
      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
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

  testWidgets('Trabajo prioriza campo y oculta los grupos sin acceso', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          user: const AuthUser(
            id: 1,
            name: 'Ana',
            email: 'ana@example.test',
            permissions: {'lotes.view', 'inventario.view'},
          ),
          onLogout: () {},
        ),
      ),
    );

    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    expect(find.text('Trabajo de campo'), findsOneWidget);
    expect(find.text('Almacenes e insumos'), findsOneWidget);
    expect(find.text('Pedidos y entregas'), findsNothing);
    expect(find.text('Calidad y administración'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Actividades')).dy,
      lessThan(tester.getTopLeft(find.text('Lotes')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Cosechas')).dy,
      lessThan(tester.getTopLeft(find.text('Almacenes')).dy),
    );
    expect(
      find.text('Revisa las tareas de campo y sus fechas.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('El inicio permite desplazarse con texto grande en un teléfono', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: HomeScreen(
          user: AuthUser(
            id: 1,
            name: 'Ana',
            email: 'ana@example.test',
            permissions: {
              for (final module in AppModule.values) module.permission,
            },
          ),
          onLogout: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Usuarios'));
    await tester.pumpAndSettle();
    expect(find.text('Consulta las cuentas de los usuarios.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Mi perfil'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(812, 375);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Usuarios'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('El botón atrás de Android vuelve de Trabajo a Inicio', (
    tester,
  ) async {
    await start(
      tester,
      (_) async => json({
        ...profile,
        'permissions': ['lotes.view'],
      }),
    );
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    expect(find.text('Tus accesos'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ver actividades'), findsOneWidget);
    expect(find.text('Tus accesos'), findsNothing);
  });

  testWidgets('Abre lotes y actividades y conserva Trabajo al regresar', (
    tester,
  ) async {
    final records = {
      '/api/lotes': [
        {
          'loteid': 7,
          'nombre': 'Parcela Los Pinos',
          'ubicacion': 'Sector norte',
          'superficie': 2.5,
        },
      ],
      '/api/actividades': [
        {
          'actividadid': 8,
          'descripcion': 'Riego de Los Pinos',
          'fecha_planificada': '2026-10-29',
        },
      ],
    };
    await start(
      tester,
      (request) async => request.url.path == '/api/me'
          ? json({
              ...profile,
              'permissions': ['lotes.view'],
            })
          : json(records[request.url.path]),
    );
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    for (final item in {
      'Lotes': 'Parcela Los Pinos',
      'Actividades': 'Riego de Los Pinos',
    }.entries) {
      await tester.ensureVisible(find.text(item.key));
      await tester.tap(find.text(item.key));
      await tester.pumpAndSettle();
      expect(find.text(item.value), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Tus accesos'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Actividades muestra carga, vacío y actualización con datos', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var calls = 0;
    await start(tester, (request) async {
      if (request.url.path == '/api/me') {
        return json({
          ...profile,
          'permissions': ['lotes.view'],
        });
      }
      if (++calls == 1) return pending.future;
      return json([
        {'actividadid': 9, 'descripcion': 'Preparar el terreno'},
      ]);
    });
    await tester.tap(find.text('Ver actividades'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Cargando actividades...'), findsOneWidget);
    pending.complete(json([]));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no hay actividades'), findsOneWidget);
    await tester.tap(find.text('Actualizar'));
    await tester.pumpAndSettle();
    expect(find.text('Preparar el terreno'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

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
      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pedidos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedidos'));
      await tester.pumpAndSettle();
      expect(find.text('SOL-009'), findsOneWidget);
      expect(find.text('Planta: Planta Sur'), findsOneWidget);
      expect(find.text('Estado: pendiente'), findsOneWidget);
      expect(find.text('Revisa los pedidos y su estado.'), findsOneWidget);
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
      expect(find.text('Todavía no hay pedidos'), findsOneWidget);
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
