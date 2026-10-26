import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/screens/home/home_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
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
};

void main() {
  const storage = SessionStorage();

  http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<ApiClient> startApp(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    SessionStorage session = storage,
    bool settle = true,
  }) async {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: session,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      AgroFusionApp(apiClient: api, sessionStorage: session),
    );
    if (settle) await tester.pumpAndSettle();
    return api;
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Sin token abre login sin consultar la API', (tester) async {
    var calls = 0;
    await startApp(tester, (_) async {
      calls++;
      return jsonResponse({}, 500);
    });
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(calls, 0);
  });

  testWidgets(
    'Restaura una sesión guardada y vuelve a consultarla al abrir de nuevo',
    (tester) async {
      await storage.saveToken('1|token-guardado');
      await startApp(tester, (_) async => jsonResponse(profile));
      expect(find.text('Hola, Ana'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await startApp(
        tester,
        (_) async => jsonResponse({...profile, 'nombre': 'Ana actualizada'}),
      );
      expect(find.text('Hola, Ana actualizada'), findsOneWidget);
      expect(await storage.readToken(), '1|token-guardado');
    },
  );

  testWidgets(
    'No muestra datos ni formularios mientras valida el token guardado',
    (tester) async {
      await storage.saveToken('1|token-guardado');
      final pending = Completer<http.Response>();
      await startApp(tester, (_) => pending.future, settle: false);
      await tester.pump();
      expect(find.text('Verificando sesión...'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      pending.complete(jsonResponse(profile));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  for (final failure in [
    (401, 'Unauthenticated.'),
    (403, 'Tu cuenta está pendiente de aprobación por un administrador.'),
    (403, 'Tu cuenta no está activa.'),
  ]) {
    testWidgets('Descarta la sesión rechazada: ${failure.$1} ${failure.$2}', (
      tester,
    ) async {
      await storage.saveToken('1|token-guardado');
      await startApp(
        tester,
        (_) async => jsonResponse({'message': failure.$2}, failure.$1),
      );
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(await storage.readToken(), isNull);
      expect(
        find.text(
          failure.$1 == 401
              ? 'La sesión dejó de ser válida. Inicia sesión de nuevo.'
              : failure.$2,
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('Conserva el token sin conexión y permite verificarlo de nuevo', (
    tester,
  ) async {
    await storage.saveToken('1|token-guardado');
    var calls = 0;
    await startApp(tester, (_) async {
      calls++;
      if (calls == 1) throw http.ClientException('offline');
      return jsonResponse(profile);
    });
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(await storage.readToken(), '1|token-guardado');
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('Permite cerrar la sesión local desde el error de restauración', (
    tester,
  ) async {
    await storage.saveToken('1|token-guardado');
    await startApp(tester, (_) async => throw http.ClientException('offline'));
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(await storage.readToken(), isNull);
    expect(
      find.text(
        'Sesión cerrada en este dispositivo. No se pudo confirmar el cierre en el servidor.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Bloquea la restauración si el almacenamiento no responde y permite reintentar',
    (tester) async {
      final failing = FailingSessionStorage();
      await failing.saveToken('1|token-guardado');
      failing.failRead = true;
      var calls = 0;
      await startApp(tester, (_) async {
        calls++;
        return jsonResponse(profile);
      }, session: failing);
      expect(calls, 0);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      failing.failRead = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(calls, 1);
    },
  );

  testWidgets(
    'Un 401 durante el uso elimina la sesión en memoria y vuelve al login',
    (tester) async {
      await storage.saveToken('1|token-guardado');
      final api = await startApp(
        tester,
        (request) async => request.url.path == '/api/me'
            ? jsonResponse(profile)
            : jsonResponse({}, 401),
      );
      await expectLater(
        api.request('GET', 'lotes'),
        throwsA(isA<ApiException>()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(await storage.readToken(), isNull);
    },
  );

  for (final status in [403, 503]) {
    testWidgets(
      'Un error $status de otro módulo conserva la sesión verificada',
      (tester) async {
        await storage.saveToken('1|token-guardado');
        final api = await startApp(
          tester,
          (request) async => request.url.path == '/api/me'
              ? jsonResponse(profile)
              : jsonResponse({}, status),
        );
        await expectLater(
          api.request('GET', 'lotes'),
          throwsA(isA<ApiException>()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(await storage.readToken(), '1|token-guardado');
      },
    );
  }

  testWidgets(
    'Un 401 con fallo de borrado bloquea el acceso hasta completar logout',
    (tester) async {
      final failing = FailingSessionStorage();
      await failing.saveToken('1|token-guardado');
      final api = await startApp(
        tester,
        (request) async => request.url.path == '/api/me'
            ? jsonResponse(profile)
            : jsonResponse({}, 401),
        session: failing,
      );
      failing.failClear = true;
      await expectLater(
        api.request('GET', 'lotes'),
        throwsA(isA<ApiException>()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      failing.failClear = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(await failing.readToken(), isNull);
    },
  );

  testWidgets(
    'Una respuesta 401 antigua no expulsa al usuario de un login nuevo',
    (tester) async {
      await storage.saveToken('1|token-anterior');
      final pending = Completer<http.Response>();
      final second = {
        ...profile,
        'usuarioid': 2,
        'nombre': 'Beatriz',
        'email': 'beatriz@example.test',
      };
      final api = await startApp(tester, (request) async {
        switch (request.url.path) {
          case '/api/lotes':
            return pending.future;
          case '/api/logout':
            return jsonResponse({});
          case '/api/login':
            return jsonResponse({'user': second, 'token': '2|token-nuevo'});
          default:
            return jsonResponse(
              request.headers['Authorization'] == 'Bearer 2|token-nuevo'
                  ? second
                  : profile,
            );
        }
      });
      final oldFailure = expectLater(
        api.request('GET', 'lotes'),
        throwsA(isA<ApiException>()),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'beatriz@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'clave-de-prueba',
      );
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Beatriz'), findsOneWidget);
      pending.complete(jsonResponse({}, 401));
      await oldFailure;
      await tester.pumpAndSettle();
      expect(find.text('Hola, Beatriz'), findsOneWidget);
      expect(await storage.readToken(), '2|token-nuevo');
    },
  );

  testWidgets(
    'Revalida al volver al primer plano y bloquea una cuenta desactivada',
    (tester) async {
      await storage.saveToken('1|token-guardado');
      var active = true;
      await startApp(
        tester,
        (_) async => active
            ? jsonResponse(profile)
            : jsonResponse({'message': 'Tu cuenta no está activa.'}, 403),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      active = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Tu cuenta no está activa.'), findsOneWidget);
      expect(await storage.readToken(), isNull);
    },
  );

  testWidgets(
    'Una restauración tardía no actualiza una aplicación desmontada',
    (tester) async {
      await storage.saveToken('1|token-guardado');
      final pending = Completer<http.Response>();
      await startApp(tester, (_) => pending.future, settle: false);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete(jsonResponse(profile));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
