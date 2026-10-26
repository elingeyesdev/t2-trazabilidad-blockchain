import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/screens/profile/profile_screen.dart';
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
  'apellido': 'Mamani',
  'email': 'ana@example.test',
  'nombreusuario': 'ana.mamani',
  'telefono': '70000000',
  'ci_nit': '00123-A',
  'activo': true,
  'estado_cuenta': 'aprobado',
  'roles': [
    {'id': 2, 'name': 'agricultor'},
    {'id': 3, 'name': 'planta'},
  ],
  'permissions': ['lotes.view', 'inventario.view'],
  'profile_capabilities': {'update_username': true, 'update_photo': true},
};

void main() {
  const storage = SessionStorage();

  http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<void> startApp(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    SessionStorage session = storage,
  }) async {
    await session.saveToken('1|token-perfil');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: session,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      AgroFusionApp(apiClient: api, sessionStorage: session),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openProfile(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Mi perfil'));
    await tester.tap(find.text('Mi perfil'));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Consulta me al abrir el perfil y actualiza también el inicio', (
    tester,
  ) async {
    var calls = 0;
    await startApp(tester, (request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/me');
      expect(request.url.query, isEmpty);
      expect(request.headers['Authorization'], 'Bearer 1|token-perfil');
      calls++;
      return jsonResponse({
        ...profile,
        'nombre': calls == 1 ? 'Ana' : 'Ana actualizada',
      });
    });
    await openProfile(tester);
    expect(calls, 2);
    expect(find.text('Ana actualizada Mamani'), findsOneWidget);
    expect(find.text('@ana.mamani'), findsOneWidget);
    expect(find.text('70000000'), findsOneWidget);
    expect(find.text('00123-A'), findsOneWidget);
    expect(find.text('Agricultor · Operador de planta'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Hola, Ana actualizada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Oculta los datos previos durante la carga y evita consultas duplicadas',
    (tester) async {
      var calls = 0;
      final pending = Completer<http.Response>();
      await startApp(tester, (_) {
        calls++;
        return calls == 1
            ? Future.value(jsonResponse(profile))
            : pending.future;
      });
      await tester.tap(find.text('Mi perfil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cargando perfil...'), findsOneWidget);
      expect(find.text('Ana Mamani'), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull,
      );
      expect(calls, 2);
      pending.complete(jsonResponse(profile));
      await tester.pumpAndSettle();
      expect(find.text('Ana Mamani'), findsOneWidget);
    },
  );

  testWidgets('La acción Actualizar perfil recupera los cambios del servidor', (
    tester,
  ) async {
    var calls = 0;
    await startApp(
      tester,
      (_) async =>
          jsonResponse({...profile, 'nombre': ++calls < 3 ? 'Ana' : 'Beatriz'}),
    );
    await openProfile(tester);
    await tester.tap(find.byTooltip('Actualizar perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Beatriz Mamani'), findsOneWidget);
    expect(find.text('Ana Mamani'), findsNothing);
  });

  testWidgets(
    'Un perfil sin datos opcionales ni roles sigue siendo consultable',
    (tester) async {
      await startApp(
        tester,
        (_) async => jsonResponse({
          'usuarioid': 1,
          'nombre': 'Ana',
          'email': 'ana@example.test',
          'activo': true,
          'estado_cuenta': 'aprobado',
        }),
      );
      await openProfile(tester);
      expect(find.text('Sin registrar'), findsWidgets);
      expect(find.text('Sin roles asignados'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Permite leer el perfil completo en una pantalla de teléfono', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await startApp(tester, (_) async => jsonResponse(profile));
    await openProfile(tester);
    await tester.ensureVisible(find.text('Último acceso'));
    await tester.pumpAndSettle();
    expect(find.text('Último acceso').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final failure in ['red', 'servidor']) {
    testWidgets('Permite recuperar el perfil después de un fallo de $failure', (
      tester,
    ) async {
      var calls = 0;
      await startApp(tester, (_) async {
        if (++calls == 2) {
          if (failure == 'red') throw http.ClientException('offline');
          return jsonResponse({}, 503);
        }
        return jsonResponse(profile);
      });
      await openProfile(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Ana Mamani'), findsNothing);
      expect(await storage.readToken(), '1|token-perfil');
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Mamani'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final status in [401, 403]) {
    testWidgets('Un me $status retira la sesión y el perfil protegido', (
      tester,
    ) async {
      var calls = 0;
      await startApp(
        tester,
        (_) async => ++calls == 1
            ? jsonResponse(profile)
            : jsonResponse({'message': 'Acceso rechazado'}, status),
      );
      await openProfile(tester);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(await storage.readToken(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Hola, Ana'), findsNothing);
    });
  }

  testWidgets('No presenta un perfil que pertenece a otro usuario', (
    tester,
  ) async {
    var calls = 0;
    await startApp(
      tester,
      (_) async => jsonResponse(
        ++calls == 1
            ? profile
            : {...profile, 'usuarioid': 2, 'nombre': 'Otra cuenta'},
      ),
    );
    await openProfile(tester);
    expect(
      find.text('La API devolvió un perfil de otra cuenta.'),
      findsOneWidget,
    );
    expect(find.text('Otra cuenta Mamani'), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets(
    'Un fallo de limpieza después de me 401 mantiene bloqueado el acceso',
    (tester) async {
      final failing = FailingSessionStorage();
      var calls = 0;
      await startApp(
        tester,
        (_) async =>
            ++calls == 1 ? jsonResponse(profile) : jsonResponse({}, 401),
        session: failing,
      );
      failing.failClear = true;
      await openProfile(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Ana Mamani'), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      failing.failClear = false;
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(await failing.readToken(), isNull);
    },
  );

  testWidgets(
    'Una foto externa no recibe el Bearer y su fallo no rompe la pantalla',
    (tester) async {
      await startApp(
        tester,
        (_) async => jsonResponse({
          ...profile,
          'avatar_url': 'https://images.example.test/foto.png',
        }),
      );
      await openProfile(tester);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).headers, isNull);
      expect(find.text('Ana Mamani'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ignora una URI local de fotografía recibida desde la API', (
    tester,
  ) async {
    await startApp(
      tester,
      (_) async => jsonResponse({
        ...profile,
        'avatar_url': 'file:///C:/privado/foto.png',
      }),
    );
    await openProfile(tester);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });
}
