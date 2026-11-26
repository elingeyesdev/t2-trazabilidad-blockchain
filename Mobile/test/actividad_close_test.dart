import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();

  const workerProfile = {
    'usuarioid': 8,
    'nombre': 'Lucía',
    'apellido': 'Quispe',
    'email': 'lucia@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 3, 'name': 'agricultor'},
    ],
    'permissions': ['lotes.view'],
  };

  const pendingActivity = {
    'actividadid': 11,
    'loteid': 25,
    'usuarioid': 8,
    'descripcion': 'Fertilización foliar',
    'fecha_planificada': '2026-11-20',
    'fechainicio': '2026-11-16T08:00:00Z',
    'fechafin': null,
    'lote': {'loteid': 25, 'nombre': 'Parcela Norte'},
    'usuario': {'usuarioid': 8, 'nombre': 'Lucía', 'apellido': 'Quispe'},
    'tipo_actividad': {'tipoactividadid': 3, 'nombre': 'Fertilización'},
    'prioridad': {'prioridadid': 2, 'nombre': 'Alta'},
  };

  XFile photoFile([String name = 'campo.png']) => XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
    name: name,
    path: name,
  );

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<void> startApp(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    Future<XFile?> Function()? capturePhoto,
    Future<XFile?> Function()? selectEvidenceFile,
  }) async {
    await storage.saveToken('1|cierre-test');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      AgroFusionApp(
        apiClient: api,
        capturePhoto: capturePhoto,
        selectEvidenceFile: selectEvidenceFile,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openActivityDetail(WidgetTester tester) async {
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Actividades'));
    await tester.tap(find.text('Actividades'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertilización foliar'));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Permite tomar y reemplazar fotografía, enviar cierre multipart y consultar el estado completado',
    (tester) async {
      var activity = Map<String, dynamic>.from(pendingActivity);
      var captureCount = 0;
      String? uploadedBody;

      await startApp(
        tester,
        (request) async {
          if (request.url.path == '/api/me') return jsonResponse(workerProfile);
          if (request.url.path == '/api/actividades' &&
              request.method == 'GET') {
            return jsonResponse([activity]);
          }
          if (request.url.path == '/api/actividades/11' &&
              request.method == 'GET') {
            return jsonResponse({'data': activity});
          }
          if (request.url.path == '/api/actividades/11/cerrar' &&
              request.method == 'POST') {
            uploadedBody = utf8.decode(request.bodyBytes, allowMalformed: true);
            activity = {
              ...activity,
              'fechafin': '2026-11-17T10:30:00Z',
              'resultado': 'Aplicación uniforme realizada',
              'evidencia_foto_url': '/api/actividades/11/evidencia',
              'completada': true,
            };
            return jsonResponse({'data': activity});
          }
          return jsonResponse({}, 404);
        },
        capturePhoto: () async {
          captureCount++;
          return photoFile(
            captureCount == 1 ? 'borrador.png' : 'evidencia-final.png',
          );
        },
      );

      await openActivityDetail(tester);
      await tester.tap(find.text('Completar y cerrar actividad'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('borrador.png'), findsOneWidget);

      await tester.ensureVisible(find.text('Tomar otra foto'));
      await tester.tap(find.text('Tomar otra foto'));
      await tester.pumpAndSettle();
      expect(find.text('evidencia-final.png'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('actividad.resultado')),
        'Aplicación uniforme realizada',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();

      expect(find.text('¿Confirmar cierre de actividad?'), findsOneWidget);
      await tester.tap(find.text('Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(uploadedBody, contains('name="resultado"'));
      expect(uploadedBody, contains('Aplicación uniforme realizada'));
      expect(uploadedBody, contains('name="evidencia_foto"'));

      expect(find.text('Detalle de actividad'), findsOneWidget);
      expect(find.text('Completada'), findsOneWidget);
      expect(find.text('Aplicación uniforme realizada'), findsOneWidget);
      expect(find.text('Completar y cerrar actividad'), findsNothing);
    },
  );

  testWidgets(
    'Conserva resultado y fotografía ante fallo de conexión y evita envíos duplicados',
    (tester) async {
      var activity = Map<String, dynamic>.from(pendingActivity);
      var closeCalls = 0;
      final secondAttempt = Completer<http.Response>();

      await startApp(
        tester,
        (request) async {
          if (request.url.path == '/api/me') return jsonResponse(workerProfile);
          if (request.url.path == '/api/actividades' &&
              request.method == 'GET') {
            return jsonResponse([activity]);
          }
          if (request.url.path == '/api/actividades/11' &&
              request.method == 'GET') {
            return jsonResponse({'data': activity});
          }
          if (request.url.path == '/api/actividades/11/cerrar' &&
              request.method == 'POST') {
            closeCalls++;
            if (closeCalls == 1) {
              throw http.ClientException('offline');
            }
            return secondAttempt.future;
          }
          return jsonResponse({}, 404);
        },
        capturePhoto: () async => throw PlatformException(
          code: 'camera_access_denied',
          message: 'Permiso denegado',
        ),
        selectEvidenceFile: () async => photoFile('galeria.png'),
      );

      await openActivityDetail(tester);
      await tester.tap(find.text('Completar y cerrar actividad'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('actividad.resultado')),
        'Trabajo terminado sin novedades',
      );
      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();
      expect(find.text('Permiso de cámara denegado'), findsOneWidget);

      await tester.ensureVisible(find.text('Elegir imagen del dispositivo'));
      await tester.tap(find.text('Elegir imagen del dispositivo'));
      await tester.pumpAndSettle();
      expect(find.text('galeria.png'), findsOneWidget);

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No se pudo conectar con el servidor. Revisa tu conexión e intenta de nuevo.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('actividad.resultado')),
            )
            .controller!
            .text,
        'Trabajo terminado sin novedades',
      );
      expect(find.text('galeria.png'), findsOneWidget);

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar cierre'));
      await tester.pump();
      await tester.tap(find.text('Cerrando actividad...'));
      await tester.pump();

      expect(closeCalls, 2);

      activity = {
        ...activity,
        'fechafin': '2026-11-17T10:35:00Z',
        'resultado': 'Trabajo terminado sin novedades',
      };
      secondAttempt.complete(jsonResponse({'data': activity}));
      await tester.pumpAndSettle();

      expect(find.text('Completada'), findsOneWidget);
      expect(find.text('Trabajo terminado sin novedades'), findsOneWidget);
    },
  );

  testWidgets(
    'Oculta el cierre al jefe agrícola y bloquea la ruta directa a usuarios no asignados',
    (tester) async {
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse({
            ...workerProfile,
            'usuarioid': 1,
            'roles': [
              {'id': 2, 'name': 'jefe_agricultor'},
            ],
          });
        }
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([pendingActivity]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': pendingActivity});
        }
        return jsonResponse({}, 404);
      });

      await openActivityDetail(tester);
      expect(find.text('Completar y cerrar actividad'), findsNothing);

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('${AppModule.actividades.route}/11/cerrar')
          .ignore();
      await tester.pumpAndSettle();
      expect(find.text('Acceso no autorizado'), findsOneWidget);
    },
  );

  testWidgets(
    'El jefe agrícola puede cambiar el responsable pendiente y cerrar si queda asignada a él',
    (tester) async {
      var assignedUserId = 8;
      var assignedUserName = 'Lucía';
      var assignedUserLast = 'Quispe';

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse({
            ...workerProfile,
            'usuarioid': 1,
            'nombre': 'Carlos',
            'apellido': 'Jefe',
            'roles': [
              {'id': 2, 'name': 'jefe_agricultor'},
            ],
            'permissions': ['lotes.view', 'lotes.update'],
          });
        }
        if (request.url.path == '/api/actividades/responsables' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [
              {
                'usuarioid': 8,
                'nombre': 'Lucía',
                'apellido': 'Quispe',
                'activo': true,
                'roles': [
                  {'id': 3, 'name': 'agricultor'},
                ],
              },
            ],
          });
        }
        Map<String, Object?> currentActivity() => {
          ...pendingActivity,
          'usuarioid': assignedUserId,
          'usuario': {
            'usuarioid': assignedUserId,
            'nombre': assignedUserName,
            'apellido': assignedUserLast,
          },
        };
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([currentActivity()]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': currentActivity()});
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          assignedUserId = body['usuarioid'] as int;
          assignedUserName = 'Carlos';
          assignedUserLast = 'Jefe';
          return jsonResponse({'data': currentActivity()});
        }
        return jsonResponse({}, 404);
      });

      await openActivityDetail(tester);
      expect(find.text('Completar y cerrar actividad'), findsNothing);
      expect(find.text('Cambiar responsable'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('actividad.cambiar_responsable')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('actividad.responsable_select')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carlos Jefe · Yo (Jefe agrícola)').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('actividad.guardar_responsable')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar cambio'));
      await tester.pumpAndSettle();

      expect(assignedUserId, 1);
      expect(find.text('Completar y cerrar actividad'), findsOneWidget);
    },
  );

  testWidgets(
    'Conserva la fotografía tomada aunque Android reanude el ciclo de vida al volver de la cámara',
    (tester) async {
      final cameraCompleter = Completer<XFile?>();

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(workerProfile);
        }
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([pendingActivity]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': pendingActivity});
        }
        return jsonResponse({}, 404);
      }, capturePhoto: () => cameraCompleter.future);

      await openActivityDetail(tester);
      await tester.tap(find.text('Completar y cerrar actividad'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pump();

      // Simula el salto a la app de cámara nativa y el retorno a Flutter.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      cameraCompleter.complete(photoFile('captura_android.jpg'));
      await tester.pumpAndSettle();

      // Incluso si llega otro resumed justo después de resolver la cámara.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Tomar otra foto'), findsOneWidget);
      expect(find.text('captura_android.jpg'), findsOneWidget);
    },
  );
}
