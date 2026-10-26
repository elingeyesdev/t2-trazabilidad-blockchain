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

  ApiClient apiWith(Future<http.Response> Function(http.Request) handler) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    return api;
  }

  Future<void> enterCredentials(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'ana@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-de-prueba');
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Solicita credenciales y no envía formularios vacíos', (
    tester,
  ) async {
    var calls = 0;
    final api = apiWith((_) async {
      calls++;
      return http.Response('', 500);
    });
    await tester.pumpWidget(AgroFusionApp(apiClient: api));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa tu correo electrónico.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('Verifica el perfil antes de mostrar el inicio autenticado', (
    tester,
  ) async {
    final confirmation = Completer<http.Response>();
    final api = apiWith(
      (request) async => request.url.path == '/api/login'
          ? jsonResponse({'user': profile, 'token': '1|token-valido'})
          : confirmation.future,
    );
    await tester.pumpWidget(AgroFusionApp(apiClient: api));
    await tester.pumpAndSettle();
    await enterCredentials(tester);
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Ingresando...'), findsOneWidget);

    confirmation.complete(jsonResponse(profile));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('ana@example.test'), findsOneWidget);
    expect(await storage.readToken(), '1|token-valido');
    expect(tester.takeException(), isNull);
  });

  for (final error in [
    (401, 'Credenciales incorrectas'),
    (403, 'Tu cuenta está pendiente de aprobación por un administrador.'),
  ]) {
    testWidgets('Muestra el error ${error.$1} y mantiene el acceso bloqueado', (
      tester,
    ) async {
      final api = apiWith(
        (_) async => jsonResponse({'message': error.$2}, error.$1),
      );
      await tester.pumpWidget(AgroFusionApp(apiClient: api));
      await tester.pumpAndSettle();
      await enterCredentials(tester);
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text(error.$2), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(await storage.readToken(), isNull);
    });
  }

  testWidgets(
    'Presenta errores de Laravel junto al campo y permite corregirlos',
    (tester) async {
      final api = apiWith(
        (_) async => jsonResponse({
          'message': 'Revisa los datos enviados.',
          'errors': {
            'email': ['El correo no es válido.'],
          },
        }, 422),
      );
      await tester.pumpWidget(AgroFusionApp(apiClient: api));
      await tester.pumpAndSettle();
      await enterCredentials(tester);
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('El correo no es válido.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).first,
        'otra@example.test',
      );
      await tester.pumpAndSettle();
      expect(find.text('El correo no es válido.'), findsNothing);
    },
  );

  testWidgets(
    'Bloquea envíos duplicados y edición mientras espera al servidor',
    (tester) async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final api = apiWith((_) {
        calls++;
        return pending.future;
      });
      await tester.pumpWidget(AgroFusionApp(apiClient: api));
      await tester.pumpAndSettle();
      await enterCredentials(tester);
      await tester.tap(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
        isFalse,
      );

      pending.complete(
        http.Response('{"message":"Credenciales incorrectas"}', 401),
      );
      await tester.pumpAndSettle();
      expect(find.text('Iniciar sesión'), findsOneWidget);
    },
  );

  testWidgets(
    'Permite mostrar la contraseña y usar una pantalla pequeña sin desbordes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = apiWith((_) async => http.Response('', 500));
      await tester.pumpWidget(AgroFusionApp(apiClient: api));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue,
      );
      await tester.ensureVisible(find.byTooltip('Mostrar contraseña'));
      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isFalse,
      );
      await tester.ensureVisible(find.byType(FilledButton));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Una respuesta tardía no notifica al controlador desmontado', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final api = apiWith((_) => pending.future);
    await tester.pumpWidget(AgroFusionApp(apiClient: api));
    await tester.pumpAndSettle();
    await enterCredentials(tester);
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpWidget(const SizedBox());
    pending.complete(
      http.Response('{"message":"Credenciales incorrectas"}', 401),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
