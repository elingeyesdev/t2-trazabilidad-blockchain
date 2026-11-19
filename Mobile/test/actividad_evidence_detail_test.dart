import 'dart:convert';
import 'dart:typed_data';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();

  final samplePngBytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );

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

  const loteNorte = {
    'loteid': 25,
    'nombre': 'Parcela Norte',
    'ubicacion': 'Valle Alto',
    'superficie': 4.5,
  };

  const completedWithEvidence = {
    'actividadid': 41,
    'loteid': 25,
    'usuarioid': 8,
    'usuarioid_ejecutor': 8,
    'descripcion': 'Aplicación de fertilizante orgánico',
    'fechainicio': '2026-11-15T08:00:00Z',
    'fechafin': '2026-11-16T15:30:00Z',
    'observaciones': 'Clima despejado durante la jornada',
    'resultado': 'Aplicación uniforme completada en toda la parcela',
    'evidencia_estado': 'disponible',
    'evidencia_foto_url': 'https://example.test/api/actividades/41/evidencia',
    'tiene_evidencia': true,
    'consumos': [
      {
        'insumoid': 101,
        'almacenid': 4,
        'cantidad': '2.5',
        'nombre': 'Fertilizante NPK',
        'unidadmedidaid': 2,
        'unidad': 'kg',
      },
      {
        'insumoid': 102,
        'almacenid': 4,
        'cantidad': '1.25',
        'nombre': 'Bioestimulante Foliar',
        'unidadmedidaid': 3,
        'unidad': 'L',
      },
    ],
    'lote': {'loteid': 25, 'nombre': 'Parcela Norte'},
    'usuario': {'usuarioid': 8, 'nombre': 'Lucía', 'apellido': 'Quispe'},
    'ejecutor': {'usuarioid': 8, 'nombre': 'Lucía', 'apellido': 'Quispe'},
    'responsable_cierre': {
      'usuarioid': 8,
      'nombre': 'Lucía',
      'apellido': 'Quispe',
    },
    'tipo_actividad': {'tipoactividadid': 3, 'nombre': 'Fertilización'},
    'prioridad': {'prioridadid': 2, 'nombre': 'Alta'},
  };

  const completedWithoutData = {
    'actividadid': 42,
    'loteid': 25,
    'usuarioid': 8,
    'descripcion': 'Control manual de malezas',
    'fechainicio': '2026-11-10T07:00:00Z',
    'fechafin': '2026-11-10T11:00:00Z',
    'resultado': null,
    'evidencia_estado': 'sin_fotografia',
    'evidencia_foto_url': null,
    'tiene_evidencia': false,
    'consumos': <Map<String, Object?>>[],
    'lote': {'loteid': 25, 'nombre': 'Parcela Norte'},
    'usuario': {'usuarioid': 8, 'nombre': 'Lucía', 'apellido': 'Quispe'},
  };

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<void> startApp(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    await storage.saveToken('1|evidencia-test');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(AgroFusionApp(apiClient: api));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Abre actividad completada desde historial del lote, muestra foto autenticada, insumos, permite ampliar y regresa al mismo historial',
    (tester) async {
      String? evidenceAuthHeader;
      final historyRequests = <String>[];

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(workerProfile);
        if (request.url.path == '/api/lotes' && request.method == 'GET') {
          return jsonResponse([loteNorte]);
        }
        if (request.url.path == '/api/lotes/25' && request.method == 'GET') {
          return jsonResponse({'data': loteNorte});
        }
        if (request.url.path == '/api/lotes/25/actividades' &&
            request.method == 'GET') {
          historyRequests.add(request.url.path);
          return jsonResponse({
            'data': [completedWithEvidence, completedWithoutData],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 2},
          });
        }
        if (request.url.path == '/api/actividades/41' &&
            request.method == 'GET') {
          return jsonResponse({'data': completedWithEvidence});
        }
        if (request.url.path == '/api/actividades/41/evidencia' &&
            request.method == 'GET') {
          evidenceAuthHeader = request.headers['Authorization'];
          return http.Response.bytes(
            samplePngBytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        return jsonResponse({}, 404);
      });

      // Navega al lote -> Historial de actividades -> Actividad completada #41.
      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lotes'));
      await tester.tap(find.text('Lotes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parcela Norte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historial de actividades'));
      await tester.pumpAndSettle();

      expect(find.text('Aplicación de fertilizante orgánico'), findsOneWidget);
      await tester.tap(find.text('Aplicación de fertilizante orgánico'));
      await tester.pumpAndSettle();

      // Verifica foto autenticada, responsable de cierre, resultado e insumos.
      expect(evidenceAuthHeader, 'Bearer 1|evidencia-test');
      expect(find.text('Fotografía de evidencia'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Responsable de cierre'), findsOneWidget);
      expect(find.text('Lucía Quispe'), findsAtLeastNWidgets(1));
      expect(
        find.text('Aplicación uniforme completada en toda la parcela'),
        findsOneWidget,
      );
      expect(find.text('Insumos utilizados'), findsOneWidget);
      expect(find.text('Fertilizante NPK'), findsOneWidget);
      expect(find.text('2.5 kg'), findsOneWidget);
      expect(find.text('Bioestimulante Foliar'), findsOneWidget);
      expect(find.text('1.25 L'), findsOneWidget);

      // Amplía la fotografía y cierra la vista ampliada.
      await tester.ensureVisible(
        find.byKey(const ValueKey('actividad.evidencia.ampliar')),
      );
      await tester.tap(
        find.byKey(const ValueKey('actividad.evidencia.ampliar')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('actividad.evidencia.viewer')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Cerrar vista ampliada'));
      await tester.pumpAndSettle();

      // Regresa al historial del mismo lote sin mezclar actividades.
      await tester.tap(find.byTooltip('Volver al historial del lote'));
      await tester.pumpAndSettle();

      expect(find.text('Historial de actividades'), findsOneWidget);
      expect(find.text('Lote #25'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Control manual de malezas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Control manual de malezas'), findsOneWidget);
      expect(
        historyRequests.every((path) => path == '/api/lotes/25/actividades'),
        isTrue,
      );
    },
  );

  testWidgets(
    'Distingue datos ausentes de un error de carga de fotografía y permite reintentar',
    (tester) async {
      var evidenceAttempts = 0;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(workerProfile);
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([completedWithEvidence, completedWithoutData]);
        }
        if (request.url.path == '/api/actividades/42' &&
            request.method == 'GET') {
          return jsonResponse({'data': completedWithoutData});
        }
        if (request.url.path == '/api/actividades/41' &&
            request.method == 'GET') {
          return jsonResponse({'data': completedWithEvidence});
        }
        if (request.url.path == '/api/actividades/41/evidencia' &&
            request.method == 'GET') {
          evidenceAttempts++;
          if (evidenceAttempts == 1) {
            return jsonResponse({'message': 'Error temporal'}, 500);
          }
          return http.Response.bytes(
            samplePngBytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        if (request.url.path == '/api/lotes/25/actividades' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [completedWithEvidence],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
          });
        }
        return jsonResponse({}, 404);
      });

      // Abre actividad #42 (datos ausentes, no error) desde el listado.
      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Actividades'));
      await tester.tap(find.text('Actividades'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Control manual de malezas'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Control manual de malezas'));
      await tester.pumpAndSettle();

      expect(
        find.text('Sin fotografía registrada para esta actividad.'),
        findsOneWidget,
      );
      expect(
        find.text('Sin insumos registrados en esta actividad.'),
        findsOneWidget,
      );
      expect(find.text('Sin resultado registrado'), findsOneWidget);
      expect(find.text('Reintentar carga'), findsNothing);

      // Vuelve al listado y abre actividad #41 donde la foto falla inicialmente con 500.
      await tester.tap(find.byTooltip('Volver a la lista'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicación de fertilizante orgánico'));
      await tester.pumpAndSettle();

      expect(evidenceAttempts, 1);
      expect(
        find.text('El servidor no está disponible. Intenta más tarde.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar carga'), findsOneWidget);

      // Reintenta cargar la fotografía y aparece la imagen + opción de ampliar.
      await tester.ensureVisible(
        find.byKey(const ValueKey('actividad.evidencia.reintentar')),
      );
      await tester.tap(
        find.byKey(const ValueKey('actividad.evidencia.reintentar')),
      );
      await tester.pumpAndSettle();

      expect(evidenceAttempts, 2);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Ampliar fotografía'), findsOneWidget);

      // Desde el detalle abierto por listado se puede ir al historial del lote correspondiente.
      await tester.ensureVisible(
        find.byKey(const ValueKey('actividad.ver_historial_lote')),
      );
      await tester.tap(
        find.byKey(const ValueKey('actividad.ver_historial_lote')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Historial de actividades'), findsOneWidget);
      expect(find.text('Lote #25'), findsOneWidget);
    },
  );
}
