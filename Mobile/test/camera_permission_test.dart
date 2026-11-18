import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/controllers/auth_controller.dart';
import 'package:agrofusion_mobile/screens/profile/profile_edit_form.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/auth_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/widgets/camera_permission_notice.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  var saved = 0;

  http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  XFile photoFile() => XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
    name: 'foto.png',
    path: 'foto.png',
  );

  Future<AuthController> startForm(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    Future<XFile?> Function()? selectFile,
    Future<XFile?> Function()? capturePhoto,
  }) async {
    await storage.saveToken('1|token-camara');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    final auth = AuthController(AuthService(api, storage));
    addTearDown(api.close);
    addTearDown(auth.dispose);
    await auth.restoreSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: auth,
            builder: (_, _) => ProfileEditForm(
              controller: auth,
              selectFile: selectFile,
              capturePhoto: capturePhoto,
              onCancel: () {},
              onSaved: () => saved++,
              onReload: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    if (find.text('Confirmar cambios').evaluate().isNotEmpty) {
      await tester.tap(find.text('Confirmar cambios'));
      await tester.pumpAndSettle();
    }
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    saved = 0;
  });

  testWidgets(
    'Explica la denegación de cámara y permite continuar eligiendo una imagen guardada',
    (tester) async {
      var writes = 0;
      await startForm(
        tester,
        (request) async {
          if (request.method != 'GET') {
            writes++;
            expect(latin1.decode(request.bodyBytes), contains('name="imagen"'));
          }
          return jsonResponse(profile);
        },
        capturePhoto: () async => throw PlatformException(
          code: 'camera_access_denied',
          message: 'Permiso denegado',
        ),
        selectFile: () async => photoFile(),
      );

      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.text('Permiso de cámara denegado'), findsOneWidget);
      expect(
        find.textContaining('El teléfono no permitió usar la cámara.'),
        findsOneWidget,
      );
      expect(find.text('Elegir imagen del dispositivo'), findsOneWidget);

      await tester.ensureVisible(find.text('Elegir imagen del dispositivo'));
      await tester.tap(find.text('Elegir imagen del dispositivo'));
      await tester.pumpAndSettle();

      expect(find.text('Permiso de cámara denegado'), findsNothing);
      expect(find.text('Quitar selección'), findsOneWidget);

      await save(tester);
      expect(writes, 1);
      expect(saved, 1);
    },
  );

  testWidgets(
    'Permite guardar otros datos del formulario aunque se deniegue la cámara',
    (tester) async {
      var writes = 0;
      await startForm(
        tester,
        (request) async {
          if (request.method == 'GET') return jsonResponse(profile);
          writes++;
          return jsonResponse({
            ...profile,
            'nombreusuario': 'ana.campo',
            'profile_capabilities': {
              'update_username': false,
              'update_photo': true,
            },
          });
        },
        capturePhoto: () async => throw const CameraPermissionException(
          'No se concedió acceso a la cámara. Puedes subir una imagen desde el dispositivo o guardar el resto de tus datos.',
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'ana.campo');
      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.text('Permiso de cámara denegado'), findsOneWidget);
      expect(
        find.text(
          'No se concedió acceso a la cámara. Puedes subir una imagen desde el dispositivo o guardar el resto de tus datos.',
        ),
        findsOneWidget,
      );

      await save(tester);
      expect(writes, 1);
      expect(saved, 1);
    },
  );

  testWidgets(
    'Tomar foto con permiso concedido carga la imagen y permite guardarla',
    (tester) async {
      var writes = 0;
      await startForm(tester, (request) async {
        if (request.method != 'GET') writes++;
        return jsonResponse(profile);
      }, capturePhoto: () async => photoFile());

      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.text('Permiso de cámara denegado'), findsNothing);
      expect(find.text('Quitar selección'), findsOneWidget);

      await save(tester);
      expect(writes, 1);
      expect(saved, 1);
    },
  );
}
