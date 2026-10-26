import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
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

  Future<void> signIn(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) logout, {
    SessionStorage session = storage,
  }) async {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: session,
      client: MockClient((request) async {
        if (request.url.path == '/api/login') {
          return jsonResponse({'user': profile, 'token': '1|token-valido'});
        }
        if (request.url.path == '/api/me') return jsonResponse(profile);
        expect(request.url.path, '/api/logout');
        return logout(request);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      AgroFusionApp(apiClient: api, sessionStorage: session),
    );
    await tester.enterText(
      find.byType(TextFormField).first,
      'ana@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-de-prueba');
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final status in [200, 401]) {
    testWidgets(
      'Cierra la sesión con respuesta $status y no vuelve al inicio mediante atrás',
      (tester) async {
        await signIn(tester, (_) async => jsonResponse({}, status));
        await tester.tap(find.byTooltip('Cerrar sesión'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.text('Sesión cerrada correctamente.'), findsOneWidget);
        expect(await storage.readToken(), isNull);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );
  }

  testWidgets('Oculta el usuario mientras cierra y bloquea envíos duplicados', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<http.Response>();
    await signIn(tester, (_) {
      calls++;
      return pending.future;
    });
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Cerrando sesión...'), findsOneWidget);
    expect(find.text('Hola, Ana'), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    pending.complete(jsonResponse({}));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('Sin conexión limpia las credenciales y explica el cierre local', (
    tester,
  ) async {
    await signIn(tester, (_) async => throw http.ClientException('offline'));
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.text(
        'Sesión cerrada en este dispositivo. No se pudo confirmar el cierre en el servidor.',
      ),
      findsOneWidget,
    );
    expect(find.byType(HomeScreen), findsNothing);
    expect(await storage.readToken(), isNull);
  });

  testWidgets(
    'Si falla el borrado local mantiene el acceso bloqueado hasta reintentar',
    (tester) async {
      final failing = FailingSessionStorage();
      var calls = 0;
      await signIn(tester, (_) async {
        calls++;
        return jsonResponse({}, calls == 1 ? 200 : 401);
      }, session: failing);
      failing.failClear = true;
      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se pudo eliminar la sesión de este dispositivo. Reintenta el cierre de sesión.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
      expect(await failing.readToken(), '1|token-valido');

      failing.failClear = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(await failing.readToken(), isNull);
      expect(calls, 2);
    },
  );

  testWidgets(
    'Una respuesta tardía de logout no actualiza un controlador desmontado',
    (tester) async {
      final pending = Completer<http.Response>();
      await signIn(tester, (_) => pending.future);
      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpWidget(const SizedBox());
      pending.complete(jsonResponse({}));
      await tester.pumpAndSettle();
      expect(await storage.readToken(), isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
