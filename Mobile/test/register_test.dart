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

const pending = {
  'message': 'Solicitud registrada. La cuenta queda pendiente de aprobación.',
  'user': {'email': 'ana@example.test', 'estado_cuenta': 'pendiente'},
};

void main() {
  const storage = SessionStorage();

  http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<void> openRegistration(
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
    await tester.ensureVisible(find.text('Crear cuenta'));
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(
    WidgetTester tester, {
    String confirmation = 'clave-de-prueba',
  }) async {
    final fields = {
      'nombre': 'Ana',
      'apellido': 'Mamani',
      'email': 'ana@example.test',
      'nombreusuario': 'ana.mamani',
      'telefono': '70000000',
      'password': 'clave-de-prueba',
      'password_confirmation': confirmation,
    };
    for (final field in fields.entries) {
      final finder = find.byKey(ValueKey('register.${field.key}'));
      await tester.ensureVisible(finder);
      await tester.enterText(finder, field.value);
      await tester.pumpAndSettle();
    }
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Solicita nombre de usuario y no envía campos obligatorios vacíos',
    (tester) async {
      var calls = 0;
      await openRegistration(tester, (_) async {
        calls++;
        return jsonResponse({}, 500);
      });
      expect(find.text('Nombre de usuario'), findsOneWidget);
      await submit(tester);
      expect(find.text('Completa este campo.'), findsWidgets);
      expect(find.text('Confirma tu contraseña.'), findsOneWidget);
      expect(calls, 0);
    },
  );

  testWidgets('Comprueba la confirmación de contraseña antes de enviar', (
    tester,
  ) async {
    var calls = 0;
    await openRegistration(tester, (_) async {
      calls++;
      return jsonResponse({}, 500);
    });
    await fillForm(tester, confirmation: 'otra-clave');
    await submit(tester);
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets(
    'El registro muestra aprobación pendiente y vuelve al login sin autenticar',
    (tester) async {
      final paths = <String>[];
      await openRegistration(tester, (request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/register') {
          return jsonResponse(pending, 201);
        }
        expect(request.url.path, '/api/login');
        return jsonResponse({
          'message':
              'Tu cuenta está pendiente de aprobación por un administrador.',
        }, 403);
      });
      await fillForm(tester);
      await submit(tester);
      expect(find.text('Solicitud enviada'), findsOneWidget);
      expect(find.text(pending['message'] as String), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(await storage.readToken(), isNull);
      expect(paths, ['/api/register']);

      await tester.tap(find.text('Volver al inicio de sesión'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[0].controller!.text, 'ana@example.test');
      expect(fields[1].controller!.text, isEmpty);

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'clave-de-prueba',
      );
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Tu cuenta está pendiente de aprobación por un administrador.',
        ),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
      expect(await storage.readToken(), isNull);
    },
  );

  testWidgets(
    'Presenta validación de Laravel y conserva los datos para corregirlos',
    (tester) async {
      await openRegistration(
        tester,
        (_) async => jsonResponse({
          'message': 'Revisa los datos enviados.',
          'errors': {
            'nombreusuario': ['Ese nombre de usuario ya está en uso.'],
          },
        }, 422),
      );
      await fillForm(tester);
      await submit(tester);
      expect(
        find.text('Ese nombre de usuario ya está en uso.'),
        findsOneWidget,
      );
      final username = find.byKey(const ValueKey('register.nombreusuario'));
      expect(
        tester.widget<TextFormField>(username).controller!.text,
        'ana.mamani',
      );
      await tester.ensureVisible(username);
      await tester.enterText(username, 'ana.mamani.2');
      await tester.pumpAndSettle();
      expect(find.text('Ese nombre de usuario ya está en uso.'), findsNothing);
    },
  );

  testWidgets(
    'El error de conexión permite volver al login sin arrastrar el mensaje',
    (tester) async {
      await openRegistration(
        tester,
        (_) async => throw http.ClientException('offline'),
      );
      await fillForm(tester);
      await submit(tester);
      const message =
          'No se pudo conectar con el servidor. Revisa tu conexión e intenta de nuevo.';
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(message), findsNothing);
    },
  );

  testWidgets(
    'Impide duplicar el registro y salir mientras espera la respuesta',
    (tester) async {
      final response = Completer<http.Response>();
      var calls = 0;
      await openRegistration(tester, (_) {
        calls++;
        return response.future;
      });
      await fillForm(tester);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Enviando solicitud...'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Enviando solicitud...'), findsOneWidget);
      response.complete(jsonResponse(pending, 201));
      await tester.pumpAndSettle();
      expect(find.text('Solicitud enviada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'El formulario se desplaza en una pantalla pequeña sin desbordes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openRegistration(tester, (_) async => jsonResponse(pending, 201));
      await fillForm(tester);
      await submit(tester);
      expect(find.text('Solicitud enviada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Una confirmación tardía no actualiza una pantalla desmontada', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var calls = 0;
    await openRegistration(tester, (_) {
      calls++;
      return response.future;
    });
    await fillForm(tester);
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    response.complete(jsonResponse(pending, 201));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
