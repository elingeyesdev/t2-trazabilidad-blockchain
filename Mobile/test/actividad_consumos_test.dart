import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
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
    'permissions': ['lotes.view', 'inventario.view'],
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

  const almacenesPayload = [
    {
      'almacenid': 4,
      'nombre': 'Almacén Agrícola Norte',
      'ubicacion': 'Sector A',
      'ambito': 'agricola',
      'activo': true,
    },
    {
      'almacenid': 9,
      'nombre': 'Bodega Comercial Centro',
      'ubicacion': 'Ciudad',
      'ambito': 'mayorista',
      'activo': true,
    },
  ];

  List<Map<String, dynamic>> buildInsumos({double npkStock = 12.5}) => [
    {
      'insumoid': 101,
      'nombre': 'Fertilizante NPK',
      'almacenid': 4,
      'unidadmedidaid': 2,
      'stock': npkStock,
      'unidad_medida': {
        'unidadmedidaid': 2,
        'nombre': 'Kilogramos',
        'abreviatura': 'kg',
      },
      'tipo': {'tipoinsumoid': 1, 'nombre': 'Fertilizante'},
    },
    {
      'insumoid': 102,
      'nombre': 'Bioestimulante Foliar',
      'almacenid': 4,
      'unidadmedidaid': 3,
      'stock': 8.0,
      'unidad_medida': {
        'unidadmedidaid': 3,
        'nombre': 'Litros',
        'abreviatura': 'L',
      },
      'tipo': {'tipoinsumoid': 2, 'nombre': 'Bioestimulante'},
    },
  ];

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
  }) async {
    await storage.saveToken('1|consumo-test');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      AgroFusionApp(apiClient: api, capturePhoto: capturePhoto),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCloseForm(WidgetTester tester) async {
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Actividades'));
    await tester.tap(find.text('Actividades'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertilización foliar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completar y cerrar actividad'));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Permite seleccionar almacén autorizado e insumo, valida stock insuficiente antes de enviar y muestra disponible/utilizado/restante',
    (tester) async {
      var activity = Map<String, dynamic>.from(pendingActivity);
      var currentStock = 12.5;
      var closeCalls = 0;
      String? uploadedBody;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(workerProfile);
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([activity]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': activity});
        }
        if (request.url.path == '/api/almacenes' && request.method == 'GET') {
          return jsonResponse(almacenesPayload);
        }
        if (request.url.path == '/api/insumos' && request.method == 'GET') {
          return jsonResponse(buildInsumos(npkStock: currentStock));
        }
        if (request.url.path == '/api/actividades/11/cerrar' &&
            request.method == 'POST') {
          closeCalls++;
          uploadedBody = utf8.decode(request.bodyBytes, allowMalformed: true);
          currentStock = 10.0;
          activity = {
            ...activity,
            'fechafin': '2026-11-18T11:00:00Z',
            'resultado': 'Aplicación foliar completa',
            'evidencia_foto_url': '/api/actividades/11/evidencia',
            'consumos': [
              {
                'insumoid': 101,
                'almacenid': 4,
                'cantidad': 2.5,
                'nombre': 'Fertilizante NPK',
                'unidadmedidaid': 2,
                'unidad': 'kg',
              },
            ],
            'completada': true,
          };
          return jsonResponse({'data': activity});
        }
        return jsonResponse({}, 404);
      }, capturePhoto: () async => photoFile('evidencia-insumo.png'));

      await openCloseForm(tester);

      // Agrega línea de consumo: solo aparece almacén agrícola autorizado.
      await tester.ensureVisible(find.byKey(const ValueKey('consumos.add')));
      await tester.tap(find.byKey(const ValueKey('consumos.add')));
      await tester.pumpAndSettle();

      expect(find.text('Almacén Agrícola Norte · Sector A'), findsOneWidget);
      expect(find.textContaining('Bodega Comercial Centro'), findsNothing);

      // Selecciona insumo Fertilizante NPK.
      await tester.ensureVisible(
        find.byKey(const ValueKey('consumo.0.insumo')),
      );
      await tester.tap(find.byKey(const ValueKey('consumo.0.insumo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertilizante NPK (12.5 kg disp.)').last);
      await tester.pumpAndSettle();

      expect(find.text('Disponible: 12.5 kg'), findsOneWidget);

      // Introduce cantidad mayor al disponible -> bloquea envío y muestra motivo.
      await tester.enterText(
        find.byKey(const ValueKey('actividad.resultado')),
        'Aplicación foliar completa',
      );
      await tester.enterText(
        find.byKey(const ValueKey('consumo.0.cantidad')),
        '20',
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Existencias insuficientes'),
        findsAtLeastNWidgets(1),
      );

      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();
      expect(closeCalls, 0);

      // Corrige cantidad a 2.5 kg -> muestra utilizado y restante, y permite cerrar.
      await tester.ensureVisible(
        find.byKey(const ValueKey('consumo.0.cantidad')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('consumo.0.cantidad')),
        '2.5',
      );
      await tester.pumpAndSettle();

      expect(find.text('Utilizado: 2.5 kg · Restante: 10 kg'), findsOneWidget);

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();

      expect(find.text('¿Confirmar cierre de actividad?'), findsOneWidget);
      expect(
        find.textContaining('Insumo: Fertilizante NPK (2.5 kg)'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(closeCalls, 1);
      expect(uploadedBody, contains('name="consumos[0][insumoid]"'));
      expect(uploadedBody, contains('101'));
      expect(uploadedBody, contains('name="consumos[0][almacenid]"'));
      expect(uploadedBody, contains('4'));
      expect(uploadedBody, contains('name="consumos[0][cantidad]"'));
      expect(uploadedBody, contains('2.5'));
      expect(uploadedBody, contains('name="consumos[0][unidadmedidaid]"'));

      // Al volver al detalle, las cantidades coinciden con las devueltas por Laravel.
      expect(find.text('Insumos utilizados'), findsOneWidget);
      expect(find.text('Fertilizante NPK'), findsOneWidget);
      expect(find.text('2.5 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'Reintento tras fallo mantiene consumos sin duplicar el descuento y coincide al volver a consultar',
    (tester) async {
      var activity = Map<String, dynamic>.from(pendingActivity);
      var currentStock = 12.5;
      var attempts = 0;
      var stockDeductedCount = 0;
      final payloads = <String>[];

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(workerProfile);
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([activity]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': activity});
        }
        if (request.url.path == '/api/almacenes' && request.method == 'GET') {
          return jsonResponse(almacenesPayload);
        }
        if (request.url.path == '/api/insumos' && request.method == 'GET') {
          return jsonResponse(buildInsumos(npkStock: currentStock));
        }
        if (request.url.path == '/api/actividades/11/cerrar' &&
            request.method == 'POST') {
          attempts++;
          payloads.add(utf8.decode(request.bodyBytes, allowMalformed: true));
          if (attempts == 1) {
            // Simula que el servidor aplicó el descuento pero la respuesta falló en red/500.
            if (stockDeductedCount == 0) {
              currentStock -= 3.25;
              stockDeductedCount++;
            }
            return jsonResponse({
              'message':
                  'No se pudo confirmar la respuesta. Reintenta el cierre.',
            }, 500);
          }
          // Segundo intento idempotente: no vuelve a descontar stock.
          activity = {
            ...activity,
            'fechafin': '2026-11-18T11:30:00Z',
            'resultado': 'Aplicación confirmada en reintento',
            'evidencia_foto_url': '/api/actividades/11/evidencia',
            'consumos': [
              {
                'insumoid': 101,
                'almacenid': 4,
                'cantidad': 3.25,
                'nombre': 'Fertilizante NPK',
                'unidadmedidaid': 2,
                'unidad': 'kg',
              },
            ],
            'completada': true,
          };
          return jsonResponse({'data': activity});
        }
        return jsonResponse({}, 404);
      }, capturePhoto: () async => photoFile('reintento.png'));

      await openCloseForm(tester);

      await tester.enterText(
        find.byKey(const ValueKey('actividad.resultado')),
        'Aplicación confirmada en reintento',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('consumos.add')));
      await tester.tap(find.byKey(const ValueKey('consumos.add')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('consumo.0.insumo')),
      );
      await tester.tap(find.byKey(const ValueKey('consumo.0.insumo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertilizante NPK (12.5 kg disp.)').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('consumo.0.cantidad')),
        '3.25',
      );
      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      // Primer intento falla con 500 y conserva resultado, foto y consumo.
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(attempts, 1);
      expect(
        find.text('El servidor no está disponible. Intenta más tarde.'),
        findsOneWidget,
      );
      expect(find.text('reintento.png'), findsOneWidget);
      expect(find.text('3.25'), findsOneWidget);

      // Reintento envía los mismos datos y cierra sin duplicar descuento.
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(stockDeductedCount, 1);
      expect(currentStock, 9.25);
      expect(payloads[0], contains('3.25'));
      expect(payloads[1], contains('3.25'));

      expect(find.text('Insumos utilizados'), findsOneWidget);
      expect(find.text('3.25 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'Ante error 422 de stock insuficiente en servidor muestra motivo y permite corregir el consumo',
    (tester) async {
      var activity = Map<String, dynamic>.from(pendingActivity);
      var currentStock = 10.0;
      var attempts = 0;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(workerProfile);
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([activity]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': activity});
        }
        if (request.url.path == '/api/almacenes' && request.method == 'GET') {
          return jsonResponse(almacenesPayload);
        }
        if (request.url.path == '/api/insumos' && request.method == 'GET') {
          return jsonResponse(buildInsumos(npkStock: currentStock));
        }
        if (request.url.path == '/api/actividades/11/cerrar' &&
            request.method == 'POST') {
          attempts++;
          if (attempts == 1) {
            currentStock = 4.0;
            return jsonResponse({
              'message': 'Stock insuficiente para el insumo seleccionado.',
              'errors': {
                'consumos.0.cantidad': [
                  'Stock insuficiente en servidor: quedan 4 kg disponibles.',
                ],
              },
            }, 422);
          }
          currentStock = 0.5;
          activity = {
            ...activity,
            'fechafin': '2026-11-18T12:00:00Z',
            'resultado': 'Consumo ajustado a existencias reales',
            'evidencia_foto_url': '/api/actividades/11/evidencia',
            'consumos': [
              {
                'insumoid': 101,
                'almacenid': 4,
                'cantidad': 3.5,
                'nombre': 'Fertilizante NPK',
                'unidadmedidaid': 2,
                'unidad': 'kg',
              },
            ],
            'completada': true,
          };
          return jsonResponse({'data': activity});
        }
        return jsonResponse({}, 404);
      }, capturePhoto: () async => photoFile('ajuste.png'));

      await openCloseForm(tester);

      await tester.enterText(
        find.byKey(const ValueKey('actividad.resultado')),
        'Consumo ajustado a existencias reales',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('consumos.add')));
      await tester.tap(find.byKey(const ValueKey('consumos.add')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('consumo.0.insumo')),
      );
      await tester.tap(find.byKey(const ValueKey('consumo.0.insumo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertilizante NPK (10 kg disp.)').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('consumo.0.cantidad')),
        '6',
      );
      await tester.ensureVisible(find.text('Tomar foto'));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(
        find.text('Stock insuficiente en servidor: quedan 4 kg disponibles.'),
        findsOneWidget,
      );

      // Actualiza existencias y corrige a 3.5 kg.
      await tester.ensureVisible(find.text('Actualizar existencias'));
      await tester.tap(find.text('Actualizar existencias'));
      await tester.pumpAndSettle();
      expect(find.text('Disponible: 4 kg'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('consumo.0.cantidad')),
        '3.5',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Cerrar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar actividad'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Insumos utilizados'), findsOneWidget);
      expect(find.text('3.5 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'Excluye insumos legacy sin almacén y fija automáticamente la semilla del lote en actividades de siembra',
    (tester) async {
      final siembraActivity = {
        'actividadid': 11,
        'loteid': 25,
        'usuarioid': 8,
        'descripcion': 'Siembra de papa',
        'fecha_planificada': '2026-11-20',
        'fechainicio': '2026-11-16T08:00:00Z',
        'fechafin': null,
        'lote': {
          'loteid': 25,
          'nombre': 'Parcela Papa',
          'insumosemillaid': 201,
          'cantidad_semilla_planificada': '15',
          'insumo_semilla': {
            'insumoid': 201,
            'almacenid': 4,
            'nombre': 'Semilla de Papa',
            'unidadmedidaid': 2,
            'unidad': 'kg',
          },
        },
        'usuario': {'usuarioid': 8, 'nombre': 'Lucía', 'apellido': 'Quispe'},
        'tipo_actividad': {'tipoactividadid': 2, 'nombre': 'Siembra'},
        'prioridad': {'prioridadid': 2, 'nombre': 'Alta'},
      };

      final mixedInsumos = [
        {
          'insumoid': 999,
          'nombre': 'Insumo Legacy Global',
          'almacenid': null,
          'unidadmedidaid': 2,
          'stock': 500,
          'unidad_medida': {'unidadmedidaid': 2, 'abreviatura': 'kg'},
          'tipo': {'tipoinsumoid': 4, 'nombre': 'Material de Siembra'},
        },
        {
          'insumoid': 201,
          'nombre': 'Semilla de Papa',
          'almacenid': 4,
          'unidadmedidaid': 2,
          'stock': 80,
          'unidad_medida': {'unidadmedidaid': 2, 'abreviatura': 'kg'},
          'tipo': {'tipoinsumoid': 4, 'nombre': 'Material de Siembra'},
        },
        {
          'insumoid': 202,
          'nombre': 'Semilla de Tomate',
          'almacenid': 4,
          'unidadmedidaid': 2,
          'stock': 50,
          'unidad_medida': {'unidadmedidaid': 2, 'abreviatura': 'kg'},
          'tipo': {'tipoinsumoid': 4, 'nombre': 'Material de Siembra'},
        },
      ];

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(workerProfile);
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([siembraActivity]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': siembraActivity});
        }
        if (request.url.path == '/api/almacenes' && request.method == 'GET') {
          return jsonResponse(almacenesPayload);
        }
        if (request.url.path == '/api/insumos' && request.method == 'GET') {
          return jsonResponse(mixedInsumos);
        }
        return jsonResponse({}, 404);
      }, capturePhoto: () async => photoFile('siembra.png'));

      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Actividades'));
      await tester.tap(find.text('Actividades'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siembra de papa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completar y cerrar actividad'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('consumo.0.insumo_locked')), findsOneWidget);
      expect(find.textContaining('Semilla de Papa'), findsWidgets);
      expect(find.text('Insumo Legacy Global'), findsNothing);
      expect(find.text('Semilla de Tomate'), findsNothing);
      expect(find.byKey(const ValueKey('consumos.add')), findsNothing);
      expect(find.byKey(const ValueKey('consumo.0.remove')), findsNothing);
    },
  );

  testWidgets(
    'Oculta insumos en Riego y exige al menos un insumo con stock en Fertilización',
    (tester) async {
      final riegoActivity = {
        ...pendingActivity,
        'descripcion': 'Riego por aspersión',
        'tipo_actividad': {'tipoactividadid': 1, 'nombre': 'Riego'},
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(workerProfile);
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([riegoActivity]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': riegoActivity});
        }
        if (request.url.path == '/api/almacenes' && request.method == 'GET') {
          return jsonResponse(almacenesPayload);
        }
        if (request.url.path == '/api/insumos' && request.method == 'GET') {
          return jsonResponse(buildInsumos());
        }
        return jsonResponse({}, 404);
      }, capturePhoto: () async => photoFile('riego.png'));

      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Actividades'));
      await tester.tap(find.text('Actividades'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riego por aspersión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completar y cerrar actividad'));
      await tester.pumpAndSettle();

      expect(find.text('Insumos utilizados'), findsNothing);
      expect(find.byKey(const ValueKey('consumos.add')), findsNothing);
    },
  );

  testWidgets(
    'Preselecciona y bloquea el pesticida asignado por el jefe al cerrar Control de plagas',
    (tester) async {
      final plagaActivity = {
        ...pendingActivity,
        'descripcion': 'Control de plagas: Pesticida Deltox (5 L)',
        'tipo_actividad': {'tipoactividadid': 4, 'nombre': 'Control de plagas'},
        'insumos_planificados': [
          {
            'insumoid': 301,
            'almacenid': 4,
            'nombre': 'Pesticida Deltox',
            'cantidad': '5',
            'unidadmedidaid': 3,
            'unidad': 'L',
          },
        ],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse({
            ...workerProfile,
            'permissions': ['lotes.view'],
          });
        }
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([plagaActivity]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': plagaActivity});
        }
        return jsonResponse({}, 404);
      }, capturePhoto: () async => photoFile('plagas.png'));

      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Actividades'));
      await tester.tap(find.text('Actividades'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Control de plagas: Pesticida Deltox (5 L)'));
      await tester.pumpAndSettle();

      // En el detalle pendiente ya muestra el insumo asignado.
      expect(find.text('Insumos asignados'), findsOneWidget);
      expect(find.text('Pesticida Deltox'), findsOneWidget);

      await tester.tap(find.text('Completar y cerrar actividad'));
      await tester.pumpAndSettle();

      // Al cerrar viene preseleccionado y bloqueado, con la cantidad precargada.
      expect(find.byKey(const ValueKey('consumo.0.insumo_locked')), findsOneWidget);
      expect(find.text('Pesticida Deltox'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.byKey(const ValueKey('consumos.add')), findsNothing);
    },
  );
}
