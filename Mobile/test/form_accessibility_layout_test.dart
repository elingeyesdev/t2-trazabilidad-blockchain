import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/controllers/auth_controller.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/screens/auth/register_screen.dart';
import 'package:agrofusion_mobile/screens/profile/profile_edit_form.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/auth_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:agrofusion_mobile/widgets/camera_permission_notice.dart';
import 'package:agrofusion_mobile/widgets/form_validation.dart';
import 'package:agrofusion_mobile/widgets/location_input_field.dart';
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
  'nombreusuario': 'ana',
  'profile_capabilities': {'update_username': true, 'update_photo': true},
};

void main() {
  const storage = SessionStorage();

  http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  void configureSmallScreenWithKeyboard(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
  }

  Widget withLargeText(Widget home) => MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.8)),
      child: child!,
    ),
    home: home,
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Login funciona con teclado abierto, texto ampliado y pantalla pequeña',
    (tester) async {
      configureSmallScreenWithKeyboard(tester);
      var loggedIn = false;
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/login') {
            loggedIn = true;
            return jsonResponse({'user': profile, 'token': '1|token-login'});
          }
          return jsonResponse(profile);
        }),
      );
      final auth = AuthController(AuthService(api, storage));
      addTearDown(api.close);
      addTearDown(auth.dispose);

      await tester.pumpWidget(withLargeText(LoginScreen(controller: auth)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(
        find.byType(TextFormField).first,
        'ana@example.test',
      );
      await tester.ensureVisible(find.byType(TextFormField).at(1));
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'clave-de-prueba',
      );
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      expect(loggedIn, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Registro funciona con teclado abierto, texto ampliado y pantalla pequeña',
    (tester) async {
      configureSmallScreenWithKeyboard(tester);
      var registered = false;
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((_) async {
          registered = true;
          return jsonResponse({
            'message':
                'Solicitud registrada. La cuenta queda pendiente de aprobación.',
            'user': {'email': 'ana@example.test', 'estado_cuenta': 'pendiente'},
          }, 201);
        }),
      );
      final auth = AuthController(AuthService(api, storage));
      addTearDown(api.close);
      addTearDown(auth.dispose);

      await tester.pumpWidget(withLargeText(RegisterScreen(controller: auth)));
      await tester.pumpAndSettle();

      final entries = {
        'nombre': 'Ana',
        'apellido': 'Mamani',
        'telefono': '70000000',
        'email': 'ana@example.test',
        'nombreusuario': 'ana.mamani',
        'password': 'clave-de-prueba',
        'password_confirmation': 'clave-de-prueba',
      };
      for (final entry in entries.entries) {
        final field = find.byKey(ValueKey('register.${entry.key}'));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, entry.value);
      }

      await tester.ensureVisible(find.text('Enviar solicitud'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar solicitud'));
      await tester.pumpAndSettle();

      expect(registered, isTrue);
      expect(find.text('Solicitud enviada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Edición de perfil y ubicación funcionan con teclado abierto, texto ampliado y pantalla pequeña',
    (tester) async {
      configureSmallScreenWithKeyboard(tester);
      var saved = 0;
      await storage.saveToken('1|token-perfil');
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient(
          (request) async => jsonResponse(
            request.method == 'GET'
                ? profile
                : {
                    ...profile,
                    'nombreusuario': 'ana.accesible',
                    'profile_capabilities': {
                      'update_username': false,
                      'update_photo': true,
                    },
                  },
          ),
        ),
      );
      final auth = AuthController(AuthService(api, storage));
      final locationController = TextEditingController();
      final locationFormKey = GlobalKey<FormState>();
      addTearDown(api.close);
      addTearDown(auth.dispose);
      addTearDown(locationController.dispose);
      await auth.restoreSession();

      await tester.pumpWidget(
        withLargeText(
          Scaffold(
            body: ListenableBuilder(
              listenable: auth,
              builder: (_, _) => ProfileEditForm(
                controller: auth,
                capturePhoto: () async =>
                    throw const CameraPermissionException(),
                onCancel: () {},
                onSaved: () => saved++,
                onReload: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), 'ana.accesible');
      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();
      expect(find.text('Permiso de cámara denegado'), findsOneWidget);

      await tester.ensureVisible(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(find.text('¿Guardar cambios del perfil?'), findsOneWidget);
      await tester.ensureVisible(find.text('Confirmar cambios'));
      await tester.tap(find.text('Confirmar cambios'));
      await tester.pumpAndSettle();
      expect(saved, 1);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        withLargeText(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: locationFormKey,
                child: Column(
                  children: [
                    LocationInputField(
                      controller: locationController,
                      requiredField: true,
                      requestLocation: () async =>
                          throw const LocationPermissionException(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => validateForm(locationFormKey),
                      child: const Text('Confirmar ubicación'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Usar ubicación actual'));
      await tester.tap(find.text('Usar ubicación actual'));
      await tester.pumpAndSettle();
      expect(find.text('Permiso de ubicación denegado'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('location.ubicacion')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.ubicacion')),
        'Parcela Sur',
      );
      await tester.ensureVisible(find.text('Confirmar ubicación'));
      await tester.tap(find.text('Confirmar ubicación'));
      await tester.pumpAndSettle();
      expect(validateForm(locationFormKey), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
