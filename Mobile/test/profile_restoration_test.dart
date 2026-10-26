import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/controllers/auth_controller.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/navigation/app_routes.dart';
import 'package:agrofusion_mobile/screens/modules/module_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/auth_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const fullProfile = {
  'usuarioid': 1,
  'nombre': 'Ana',
  'apellido': 'Mamani',
  'email': 'ana@example.test',
  'nombreusuario': 'ana.inicial',
  'telefono': '70000000',
  'ci_nit': '00123-A',
  'activo': true,
  'estado_cuenta': 'aprobado',
  'avatar_url': null,
  'nombreusuario_editado': false,
  'fecharegistro': '2026-10-20T12:00:00Z',
  'fechamodificacion': '2026-10-25T12:00:00Z',
  'ultimologin': '2026-10-26T12:00:00Z',
  'roles': [
    {'name': 'agricultor'},
    {'name': 'operador_planta'},
  ],
  'permissions': ['lotes.view', 'inventario.view'],
  'profile_capabilities': {'update_username': true, 'update_photo': true},
};

final changedProfile = {
  ...fullProfile,
  'nombre': 'Ana actualizada',
  'nombreusuario': 'ana.nueva',
  'telefono': '71111111',
  'nombreusuario_editado': true,
  'roles': [
    {'name': 'transportista'},
  ],
  'permissions': ['pedidos.view'],
  'profile_capabilities': {'update_username': false, 'update_photo': true},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = SessionStorage();

  http.Response json(Object? body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  ApiClient api(Future<http.Response> Function(http.Request) handler) {
    final client = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(client.close);
    return client;
  }

  AuthController controller(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final auth = AuthController(AuthService(api(handler), storage));
    addTearDown(auth.dispose);
    return auth;
  }

  Future<void> start(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    await tester.pumpWidget(AgroFusionApp(apiClient: api(handler)));
    await tester.pumpAndSettle();
  }

  void resume(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Future<void> push(
    WidgetTester tester,
    String route, {
    bool settle = true,
  }) async {
    unawaited(
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|restauracion');
  });

  test(
    'Restaura el perfil completo y sustituye permisos, roles y capacidades',
    () async {
      Map<String, Object?> current = fullProfile;
      final auth = controller((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/me');
        expect(request.headers['Authorization'], 'Bearer 1|restauracion');
        return json(current);
      });
      await auth.restoreSession();
      expect(auth.user!.fullName, 'Ana Mamani');
      expect(auth.user!.identityDocument, '00123-A');
      expect(auth.user!.registeredAt, DateTime.parse('2026-10-20T12:00:00Z'));
      expect(auth.user!.roles, ['agricultor', 'operador_planta']);
      expect(auth.user!.permissions, {'lotes.view', 'inventario.view'});
      expect(auth.user!.canUpdateUsername, isTrue);

      current = {
        ...changedProfile,
        'avatar_url': 'https://example.test/foto-nueva.png',
      };
      await auth.restoreSession();
      expect(auth.user!.username, 'ana.nueva');
      expect(auth.user!.phone, '71111111');
      expect(auth.user!.avatarUrl, 'https://example.test/foto-nueva.png');
      expect(auth.user!.roles, ['transportista']);
      expect(auth.user!.permissions, {'pedidos.view'});
      expect(auth.user!.canUpdateUsername, isFalse);
      expect(auth.user!.canUpdatePhoto, isTrue);

      current = {
        'usuarioid': 1,
        'nombre': 'Ana',
        'email': 'ana@example.test',
        'activo': true,
        'estado_cuenta': 'aprobado',
      };
      await auth.restoreSession();
      expect(auth.user!.roles, isEmpty);
      expect(auth.user!.permissions, isEmpty);
      expect(auth.user!.canUpdateUsername, isFalse);
      expect(auth.user!.canUpdatePhoto, isFalse);
      expect(await const FlutterSecureStorage().readAll(), {
        'agrofusion.auth_token': '1|restauracion',
      });
    },
  );

  test(
    'Conserva la identidad esperada durante la revalidación y sus reintentos',
    () async {
      var calls = 0;
      final auth = controller(
        (_) async => json(
          ++calls == 1 || calls == 4
              ? fullProfile
              : {
                  ...changedProfile,
                  'usuarioid': 2,
                  'nombre': 'Otra cuenta',
                  'permissions': ['usuarios.admin'],
                },
        ),
      );
      await auth.restoreSession();
      for (var attempt = 0; attempt < 2; attempt++) {
        await auth.restoreSession();
        expect(auth.user, isNull);
        expect(
          auth.sessionError!.message,
          'La API devolvió un perfil de otra cuenta.',
        );
        expect(await storage.readToken(), '1|restauracion');
      }
      await auth.restoreSession();
      expect(auth.user!.id, 1);
      expect(auth.user!.permissions, {'lotes.view', 'inventario.view'});
      expect(auth.sessionError, isNull);
    },
  );

  test(
    'Descarta los permisos de una restauración tardía si se reemplazó el token',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final auth = controller((_) {
        started.complete();
        return pending.future;
      });
      final restoring = auth.restoreSession();
      await started.future;
      await storage.saveToken('2|nueva-sesion');
      pending.complete(
        json({
          ...fullProfile,
          'permissions': ['usuarios.admin'],
        }),
      );
      await restoring;
      expect(auth.user, isNull);
      expect(auth.sessionError!.message, contains('La sesión cambió'));
      expect(await storage.readToken(), '2|nueva-sesion');
    },
  );

  test(
    'Un cierre explícito permite iniciar otra cuenta con sus propios permisos',
    () async {
      final newUser = {...changedProfile, 'usuarioid': 2, 'nombre': 'Beatriz'};
      var afterLogout = false;
      final auth = controller((request) async {
        if (request.url.path == '/api/logout') {
          afterLogout = true;
          return json({});
        }
        if (request.url.path == '/api/login') {
          return json({'user': newUser, 'token': '2|nueva-sesion'});
        }
        return json(afterLogout ? newUser : fullProfile);
      });
      await auth.restoreSession();
      await auth.logout();
      expect(await auth.login('beatriz@example.test', 'clave'), isTrue);
      expect(auth.user!.id, 2);
      expect(auth.user!.permissions, {'pedidos.view'});
      await auth.restoreSession();
      expect(auth.user!.id, 2);
      expect(auth.sessionError, isNull);
    },
  );

  testWidgets(
    'Al abrir de nuevo usa el perfil y los permisos vigentes sin otro login',
    (tester) async {
      await start(tester, (_) async => json(fullProfile));
      expect(find.text('Lotes'), findsOneWidget);
      expect(find.text('Pedidos'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await start(tester, (request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/me');
        return json(changedProfile);
      });
      expect(find.text('Hola, Ana actualizada'), findsOneWidget);
      expect(find.text('Pedidos'), findsOneWidget);
      expect(find.text('Lotes'), findsNothing);
      await push(tester, AppRoutes.profile);
      expect(find.text('Ana actualizada Mamani'), findsOneWidget);
      expect(find.text('@ana.nueva'), findsOneWidget);
      expect(find.text('71111111'), findsOneWidget);
      expect(find.text('Transportista'), findsOneWidget);
      expect(await storage.readToken(), '1|restauracion');
    },
  );

  for (final retainPermission in [false, true]) {
    testWidgets(
      'Revalida un destino abierto y descarta su respuesta anterior, conserva permiso: $retainPermission',
      (tester) async {
        final oldModule = Completer<http.Response>();
        final freshProfile = Completer<http.Response>();
        var meCalls = 0;
        var moduleCalls = 0;
        await start(tester, (request) {
          if (request.url.path == '/api/me') {
            return ++meCalls == 1
                ? Future.value(json(changedProfile))
                : freshProfile.future;
          }
          return ++moduleCalls == 1
              ? oldModule.future
              : Future.value(
                  json([
                    {'pedidoid': 2, 'numero_solicitud': 'Registro vigente'},
                  ]),
                );
        });
        await push(tester, AppModule.pedidos.route, settle: false);
        resume(tester);
        await tester.pump();
        expect(find.text('Verificando sesión...'), findsWidgets);
        expect(find.byType(ModuleScreen), findsNothing);
        freshProfile.complete(
          json({
            ...changedProfile,
            'permissions': retainPermission ? ['pedidos.view'] : [],
          }),
        );
        await tester.pumpAndSettle();
        oldModule.complete(
          json([
            {'pedidoid': 1, 'numero_solicitud': 'Registro anterior'},
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.text('Registro anterior'), findsNothing);
        expect(
          find.text('Registro vigente'),
          retainPermission ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Acceso no autorizado'),
          retainPermission ? findsNothing : findsOneWidget,
        );
        expect(meCalls, 2);
        expect(moduleCalls, retainPermission ? 2 : 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Al volver al primer plano incorpora permisos directos nuevos sin depender del rol',
    (tester) async {
      var calls = 0;
      await start(
        tester,
        (_) async => json({
          ...fullProfile,
          'roles': [],
          'permissions': ++calls == 1 ? [] : ['pedidos.view'],
        }),
      );
      expect(find.text('Pedidos'), findsNothing);
      resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Pedidos'), findsOneWidget);
      expect(find.text('Lotes'), findsNothing);
      expect(calls, 2);
    },
  );

  testWidgets(
    'Sin conexión al reanudar bloquea el menú anterior hasta recuperar permisos actuales',
    (tester) async {
      var calls = 0;
      await start(tester, (_) async {
        calls++;
        if (calls == 2) throw http.ClientException('offline');
        return json(calls == 1 ? fullProfile : changedProfile);
      });
      resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Lotes'), findsNothing);
      expect(find.text('Mi perfil'), findsNothing);
      expect(await storage.readToken(), '1|restauracion');
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Pedidos'), findsOneWidget);
      expect(find.text('Lotes'), findsNothing);
      expect(find.text('Hola, Ana actualizada'), findsOneWidget);
      expect(calls, 3);
    },
  );
}
