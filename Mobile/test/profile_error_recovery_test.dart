import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/controllers/auth_controller.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/screens/profile/profile_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/auth_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers/failing_session_storage.dart';

const profile = {
  'usuarioid': 1,
  'nombre': 'Ana',
  'email': 'ana@example.test',
  'activo': true,
  'estado_cuenta': 'aprobado',
  'nombreusuario': 'ana',
  'permissions': ['pedidos.view'],
  'profile_capabilities': {'update_username': true, 'update_photo': true},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = SessionStorage();
  http.Response json(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  ApiClient api(
    Future<http.Response> Function(http.Request) handler,
    SessionStorage session,
  ) {
    final client = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: session,
      client: MockClient(handler),
    );
    addTearDown(client.close);
    return client;
  }

  Future<void> push(WidgetTester tester, String route) async {
    unawaited(
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'La pérdida del token local retira la sesión al consultar un módulo',
    (tester) async {
      await storage.saveToken('1|errores');
      final client = api((request) async {
        if (request.url.path == '/api/me') return json(profile);
        expect(request.headers['Authorization'], isNull);
        return json({}, 401);
      }, storage);
      await tester.pumpWidget(AgroFusionApp(apiClient: client));
      await tester.pumpAndSettle();

      await storage.clearToken();
      await push(tester, AppModule.pedidos.route);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Hola, Ana'), findsNothing);
      expect(await storage.readToken(), isNull);
    },
  );

  for (final revalidation in ['perfil', 'reanudación']) {
    for (final failCleanup in [false, true]) {
      testWidgets(
        'Un 401 concurrente no permite recuperar un perfil anterior durante $revalidation, falla limpieza: $failCleanup',
        (tester) async {
          final session = FailingSessionStorage();
          await session.saveToken('1|errores');
          final pendingProfile = Completer<http.Response>();
          final pendingModule = Completer<http.Response>();
          final moduleStarted = Completer<void>();
          var meCalls = 0;
          final client = api((request) {
            if (request.url.path == '/api/me') {
              return ++meCalls == 1
                  ? Future.value(json(profile))
                  : pendingProfile.future;
            }
            if (request.url.path == '/api/logout') {
              return Future.value(json({}));
            }
            moduleStarted.complete();
            return pendingModule.future;
          }, session);
          await tester.pumpWidget(
            AgroFusionApp(apiClient: client, sessionStorage: session),
          );
          await tester.pumpAndSettle();
          final expired = expectLater(
            client.request('GET', 'pedidos'),
            throwsA(isA<ApiException>()),
          );
          await moduleStarted.future;
          if (revalidation == 'perfil') {
            await tester.tap(find.text('Mi perfil'));
          } else {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(meCalls, 2);
          session.failClear = failCleanup;
          pendingModule.complete(json({}, 401));
          await expired;
          pendingProfile.complete(
            json({...profile, 'nombre': 'Respuesta anterior'}),
          );
          await tester.pumpAndSettle();
          expect(find.text('Respuesta anterior'), findsNothing);
          expect(find.byType(ProfileScreen), findsNothing);
          if (failCleanup) {
            expect(find.byType(LoginScreen), findsNothing);
            expect(find.text('Reintentar'), findsOneWidget);
            session.failClear = false;
            await tester.tap(find.text('Reintentar'));
            await tester.pumpAndSettle();
          }
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(await session.readToken(), isNull);
        },
      );
    }
  }

  test(
    'Un guardado anterior no restablece al usuario tras un 401 con limpieza fallida',
    () async {
      final session = FailingSessionStorage();
      await session.saveToken('1|errores');
      final pendingWrite = Completer<http.Response>();
      final writeStarted = Completer<void>();
      final client = api((request) {
        if (request.url.path == '/api/pedidos') {
          return Future.value(json({}, 401));
        }
        if (request.method == 'PATCH') {
          writeStarted.complete();
          return pendingWrite.future;
        }
        return Future.value(json(profile));
      }, session);
      final auth = AuthController(AuthService(client, session));
      addTearDown(auth.dispose);
      await auth.restoreSession();
      final saving = auth.updateProfile(username: 'ana.nueva');
      await writeStarted.future;
      session.failClear = true;
      await expectLater(
        client.request('GET', 'pedidos'),
        throwsA(isA<ApiException>()),
      );
      pendingWrite.complete(json({...profile, 'nombreusuario': 'ana.nueva'}));
      expect(await saving, isFalse);
      expect(auth.user, isNull);
      expect(auth.requiresLogoutRetry, isTrue);
    },
  );

  for (final granted in [false, true]) {
    testWidgets(
      'Actualizar permisos recupera la autorización vigente, concedido: $granted',
      (tester) async {
        await storage.saveToken('1|errores');
        var meCalls = 0;
        var moduleCalls = 0;
        final client = api((request) async {
          if (request.url.path == '/api/me') {
            return json({
              ...profile,
              'permissions': ++meCalls == 1 || granted ? ['pedidos.view'] : [],
            });
          }
          moduleCalls++;
          return moduleCalls == 1
              ? json({}, 403)
              : json([
                  {'pedidoid': 4, 'numero_solicitud': 'Consulta recuperada'},
                ]);
        }, storage);
        await tester.pumpWidget(AgroFusionApp(apiClient: client));
        await tester.pumpAndSettle();
        await push(tester, AppModule.pedidos.route);
        expect(find.text('Acceso no autorizado'), findsOneWidget);
        await tester.tap(find.text('Actualizar permisos'));
        await tester.pumpAndSettle();
        expect(meCalls, 2);
        expect(moduleCalls, granted ? 2 : 1);
        if (granted) {
          expect(find.text('Consulta recuperada'), findsOneWidget);
          await tester.pageBack();
        } else {
          expect(find.text('Acceso no autorizado'), findsOneWidget);
          await tester.tap(find.text('Volver al inicio'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Hola, Ana'), findsOneWidget);
        expect(find.text('Pedidos'), granted ? findsOneWidget : findsNothing);
        expect(await storage.readToken(), '1|errores');
      },
    );
  }
}
