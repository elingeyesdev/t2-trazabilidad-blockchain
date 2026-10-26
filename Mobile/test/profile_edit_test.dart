import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/controllers/auth_controller.dart';
import 'package:agrofusion_mobile/screens/profile/profile_edit_form.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/auth_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:file_selector/file_selector.dart';
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
  var saved = 0;
  var reloaded = 0;
  http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<AuthController> startForm(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    Future<XFile?> Function()? selectFile,
  }) async {
    await storage.saveToken('1|token-perfil');
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
              onCancel: () {},
              onSaved: () => saved++,
              onReload: () => reloaded++,
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
  }

  XFile photoFile() => XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
    name: 'foto.png',
    path: 'foto.png',
  );
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    saved = 0;
    reloaded = 0;
  });

  testWidgets('No envía el nombre sin cambios ni permite un nombre vacío', (
    tester,
  ) async {
    var writes = 0;
    await startForm(tester, (request) async {
      if (request.method != 'GET') writes++;
      return jsonResponse(profile);
    });
    await save(tester);
    expect(find.text('No hay cambios para guardar.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '');
    await save(tester);
    expect(find.text('Ingresa un nombre de usuario.'), findsOneWidget);
    expect(writes, 0);
  });

  testWidgets('Guarda el nombre y utiliza las capacidades de la respuesta', (
    tester,
  ) async {
    final auth = await startForm(
      tester,
      (request) async => jsonResponse(
        request.method == 'GET'
            ? profile
            : {
                ...profile,
                'nombreusuario': 'ana.nueva',
                'profile_capabilities': {
                  'update_username': false,
                  'update_photo': true,
                },
              },
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'ana.nueva');
    await save(tester);
    expect(saved, 1);
    expect(auth.user!.username, 'ana.nueva');
    expect(auth.user!.canUpdateUsername, isFalse);
  });

  testWidgets(
    'Permite cambiar la foto con el nombre bloqueado y no lo reenvía',
    (tester) async {
      final locked = {
        ...profile,
        'profile_capabilities': {
          'update_username': false,
          'update_photo': true,
        },
      };
      var writes = 0;
      await startForm(tester, (request) async {
        if (request.method != 'GET') {
          writes++;
          expect(
            latin1.decode(request.bodyBytes),
            isNot(contains('name="nombreusuario"')),
          );
          expect(latin1.decode(request.bodyBytes), contains('name="imagen"'));
        }
        return jsonResponse(locked);
      }, selectFile: () async => photoFile());
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('Seleccionar foto'));
      await tester.pumpAndSettle();
      expect(find.text('Quitar selección'), findsOneWidget);
      await save(tester);
      expect(writes, 1);
      expect(saved, 1);
    },
  );

  testWidgets('Cancelar el selector no cambia la foto ni envía una escritura', (
    tester,
  ) async {
    var writes = 0;
    await startForm(tester, (request) async {
      if (request.method != 'GET') writes++;
      return jsonResponse(profile);
    }, selectFile: () async => null);
    await tester.tap(find.text('Seleccionar foto'));
    await tester.pumpAndSettle();
    expect(find.text('Quitar selección'), findsNothing);
    await save(tester);
    expect(writes, 0);
  });

  testWidgets('Rechaza una fotografía demasiado grande antes de subirla', (
    tester,
  ) async {
    var writes = 0;
    await startForm(
      tester,
      (request) async {
        if (request.method != 'GET') writes++;
        return jsonResponse(profile);
      },
      selectFile: () async =>
          XFile.fromData(Uint8List(2097153), name: 'foto.png'),
    );
    await tester.tap(find.text('Seleccionar foto'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona una imagen de hasta 2 MB.'), findsOneWidget);
    expect(writes, 0);
  });

  testWidgets('Presenta errores 422 y conserva el nombre escrito', (
    tester,
  ) async {
    await startForm(
      tester,
      (request) async => request.method == 'GET'
          ? jsonResponse(profile)
          : jsonResponse({
              'message': 'Revisa los datos',
              'errors': {
                'nombreusuario': ['Nombre no disponible'],
              },
            }, 422),
    );
    await tester.enterText(find.byType(TextFormField), 'ana.ocupada');
    await save(tester);
    expect(find.text('Nombre no disponible'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'ana.ocupada',
    );
    expect(saved, 0);
  });

  testWidgets('Un aviso anterior no oculta el error de una fotografía nueva', (
    tester,
  ) async {
    await startForm(
      tester,
      (_) async => jsonResponse(profile),
      selectFile: () async =>
          XFile.fromData(Uint8List(2097153), name: 'foto.png'),
    );
    await save(tester);
    expect(find.text('No hay cambios para guardar.'), findsOneWidget);

    await tester.tap(find.text('Seleccionar foto'));
    await tester.pumpAndSettle();

    expect(find.text('Selecciona una imagen de hasta 2 MB.'), findsOneWidget);
    expect(find.text('No hay cambios para guardar.'), findsNothing);
  });

  testWidgets('Ante un 403 recupera capacidades sin cerrar una sesión válida', (
    tester,
  ) async {
    var rejected = false;
    final auth = await startForm(tester, (request) async {
      if (request.method != 'GET') {
        rejected = true;
        return jsonResponse({'message': 'Cambio rechazado'}, 403);
      }
      return jsonResponse(
        rejected
            ? {
                ...profile,
                'profile_capabilities': {
                  'update_username': false,
                  'update_photo': true,
                },
              }
            : profile,
      );
    });
    await tester.enterText(find.byType(TextFormField), 'ana.nueva');
    await save(tester);
    expect(auth.user, isNotNull);
    expect(find.text('Cambio rechazado'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Seleccionar foto'), findsOneWidget);
  });

  testWidgets(
    'Un guardado incierto exige consultar antes de repetir la escritura',
    (tester) async {
      var writes = 0;
      await startForm(tester, (request) async {
        if (request.method == 'GET') return jsonResponse(profile);
        writes++;
        throw http.ClientException('offline');
      });
      await tester.enterText(find.byType(TextFormField), 'ana.nueva');
      await save(tester);
      await save(tester);
      expect(writes, 1);
      await tester.tap(find.text('Consultar perfil'));
      await tester.pumpAndSettle();
      expect(reloaded, 1);
      expect(saved, 0);
    },
  );

  testWidgets(
    'Mantiene el formulario durante la selección y revalida al terminar',
    (tester) async {
      var reads = 0;
      final pending = Completer<XFile?>();
      final auth = await startForm(tester, (_) async {
        reads++;
        return jsonResponse(profile);
      }, selectFile: () => pending.future);
      await tester.enterText(find.byType(TextFormField), 'ana.borrador');
      await tester.tap(find.text('Seleccionar foto'));
      await tester.pump();
      await auth.restoreSession();
      expect(reads, 1);
      pending.complete(photoFile());
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'ana.borrador',
      );
      expect(find.text('Quitar selección'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
