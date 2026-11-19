import 'dart:convert';

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

  const agricultorProfile = {
    'usuarioid': 8,
    'nombre': 'Lucía',
    'apellido': 'Quispe',
    'email': 'lucia@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 3, 'name': 'agricultor'},
    ],
    'permissions': ['lotes.view', 'catalogos.view'],
  };

  const lotesPayload = [
    {
      'loteid': 25,
      'nombre': 'Parcela Norte',
      'ubicacion': 'Valle Alto',
      'superficie': 4.5,
      'cultivo': {'cultivoid': 1, 'nombre': 'Papa'},
    },
  ];

  const unidadesPayload = [
    {
      'unidadmedidaid': 1,
      'nombre': 'Kilogramos',
      'abreviatura': 'kg',
      'categoria': 'peso',
    },
    {
      'unidadmedidaid': 2,
      'nombre': 'Quintales',
      'abreviatura': 'qq',
      'categoria': 'peso',
    },
    {
      'unidadmedidaid': 9,
      'nombre': 'Litros',
      'abreviatura': 'L',
      'categoria': 'volumen',
    },
  ];

  const presentacionesConfig = {
    'predeterminada_id': 14,
    'presentaciones': [
      {
        'catalogotamanoconteoid': 14,
        'nombre': 'Calibre Grande',
        'peso_promedio_kg': '0.250',
        'conteo_por_empaque': 40,
        'empaque': 'Caja de cartón',
      },
      {
        'catalogotamanoconteoid': 15,
        'nombre': 'Calibre Mediano',
        'peso_promedio_kg': '0.180',
        'conteo_por_empaque': 50,
        'empaque': 'Caja de cartón',
      },
    ],
  };

  const existingCosecha = {
    'produccionid': 70,
    'loteid': 25,
    'cantidad': '100.000',
    'unidadmedidaid': 1,
    'unidad': 'kg',
    'cantidad_base': '100.000000',
    'cantidadkg': '100.000000',
    'catalogotamanoconteoid': 14,
    'cantidad_unidades': 400,
    'cantidad_empaques': 10,
    'fechacosecha': '2026-11-10',
    'observaciones': 'Cosecha inicial seca',
    'lote': {'loteid': 25, 'nombre': 'Parcela Norte'},
    'presentacion': {
      'ok': true,
      'kg': '100.000000',
      'unidades': 400,
      'empaques': 10,
      'empaque_label': 'Cajas',
      'calibre_nombre': 'Calibre Grande',
      'calibre_id': 14,
      'conteo_por_empaque': 40,
      'peso_promedio_kg': '0.250',
      'resumen': '10 Cajas · 400 unidades',
    },
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
    await storage.saveToken('1|cosecha-test');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(AgroFusionApp(apiClient: api));
    await tester.pumpAndSettle();
  }

  Future<void> openCosechas(WidgetTester tester) async {
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cosechas'));
    await tester.tap(find.text('Cosechas'));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Registra una cosecha con lote autorizado, presentación, cantidad y fecha, y muestra cantidades y equivalencias del servidor',
    (tester) async {
      final cosechas = <Map<String, dynamic>>[existingCosecha];
      Map<String, dynamic>? sentBody;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(agricultorProfile);
        }
        if (request.url.path == '/api/producciones' &&
            request.method == 'GET') {
          return jsonResponse(cosechas);
        }
        if (request.url.path == '/api/lotes' && request.method == 'GET') {
          return jsonResponse(lotesPayload);
        }
        if (request.url.path == '/api/unidadesmedida' &&
            request.method == 'GET') {
          return jsonResponse(unidadesPayload);
        }
        if (request.url.path == '/api/lotes/25/presentaciones-cosecha' &&
            request.method == 'GET') {
          return jsonResponse(presentacionesConfig);
        }
        if (request.url.path == '/api/producciones' &&
            request.method == 'POST') {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          final created = {
            'produccionid': 71,
            'loteid': 25,
            'cantidad': '2.5',
            'unidadmedidaid': 2,
            'unidad': 'qq',
            'cantidad_base': '115.000000',
            'cantidadkg': '115.000000',
            'catalogotamanoconteoid': 14,
            'cantidad_unidades': 460,
            'cantidad_empaques': 12,
            'fechacosecha': '2026-11-19',
            'observaciones': 'Cosecha de mañana',
            'lote': {'loteid': 25, 'nombre': 'Parcela Norte'},
            'presentacion': {
              'ok': true,
              'kg': '115.000000',
              'unidades': 460,
              'empaques': 12,
              'empaque_label': 'Cajas',
              'calibre_nombre': 'Calibre Grande',
              'calibre_id': 14,
              'conteo_por_empaque': 40,
              'peso_promedio_kg': '0.250',
              'resumen': '12 Cajas · 460 unidades',
            },
          };
          cosechas.insert(0, created);
          return jsonResponse(created, 201);
        }
        if (request.url.path == '/api/producciones/71' &&
            request.method == 'GET') {
          return jsonResponse(cosechas.first);
        }
        return jsonResponse({}, 404);
      });

      await openCosechas(tester);

      await tester.tap(find.text('Registrar cosecha'));
      await tester.pumpAndSettle();

      // Solo lote autorizado (auto-seleccionado) y presentación predeterminada cargada.
      expect(find.text('Parcela Norte · Papa'), findsOneWidget);
      expect(
        find.textContaining('Calibre Grande · Caja de cartón'),
        findsOneWidget,
      );

      // Selecciona unidad Quintales (qq), cantidad y fecha.
      await tester.ensureVisible(find.byKey(const ValueKey('cosecha.unidad')));
      await tester.tap(find.byKey(const ValueKey('cosecha.unidad')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Litros'), findsNothing);
      await tester.tap(find.text('Quintales (qq)').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('cosecha.cantidad')),
        '2.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cosecha.fecha')),
        '2026-11-19',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cosecha.observaciones')),
        'Cosecha de mañana',
      );

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Registrar cosecha'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar cosecha'));
      await tester.pumpAndSettle();

      expect(find.text('¿Registrar cosecha?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar registro'));
      await tester.pumpAndSettle();

      expect(sentBody, isNotNull);
      expect(sentBody!['loteid'], 25);
      expect(sentBody!['cantidad'], '2.5');
      expect(sentBody!['unidadmedidaid'], 2);
      expect(sentBody!['catalogotamanoconteoid'], 14);
      expect(sentBody!['fechacosecha'], '2026-11-19');
      expect(sentBody!.containsKey('cantidad_base'), isFalse);
      expect(sentBody!.containsKey('cantidad_unidades'), isFalse);

      // El detalle muestra las cantidades y equivalencias devueltas por el servidor.
      expect(find.text('Detalle de cosecha'), findsOneWidget);
      expect(find.text('2.5 qq'), findsOneWidget);
      expect(find.text('Cantidades y equivalencias'), findsOneWidget);
      expect(find.text('115 kg'), findsOneWidget);
      expect(find.text('12 Cajas · 460 unidades'), findsOneWidget);
      expect(find.text('460 unidades'), findsOneWidget);
    },
  );

  testWidgets(
    'Muestra validaciones de Laravel junto al campo correspondiente y permite buscar y abrir detalle de cosechas',
    (tester) async {
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(agricultorProfile);
        }
        if (request.url.path == '/api/producciones' &&
            request.method == 'GET') {
          return jsonResponse([existingCosecha]);
        }
        if (request.url.path == '/api/producciones/70' &&
            request.method == 'GET') {
          return jsonResponse(existingCosecha);
        }
        if (request.url.path == '/api/lotes' && request.method == 'GET') {
          return jsonResponse(lotesPayload);
        }
        if (request.url.path == '/api/unidadesmedida' &&
            request.method == 'GET') {
          return jsonResponse(unidadesPayload);
        }
        if (request.url.path == '/api/lotes/25/presentaciones-cosecha' &&
            request.method == 'GET') {
          return jsonResponse(presentacionesConfig);
        }
        if (request.url.path == '/api/producciones' &&
            request.method == 'POST') {
          return jsonResponse({
            'message': 'Revisa los datos de la cosecha.',
            'errors': {
              'cantidad': [
                'La cantidad supera el límite permitido para el lote.',
              ],
              'fechacosecha': [
                'La fecha de cosecha no puede ser anterior a la siembra.',
              ],
            },
          }, 422);
        }
        return jsonResponse({}, 404);
      });

      await openCosechas(tester);

      // Prueba búsqueda y apertura de detalle.
      await tester.tap(find.byTooltip('Buscar cosechas'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Calibre Grande');
      await tester.pumpAndSettle();
      expect(find.text('Cosecha #70'), findsOneWidget);
      await tester.tap(find.text('Cosecha #70'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de cosecha'), findsOneWidget);
      expect(find.text('10 Cajas · 400 unidades'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver a la lista'));
      await tester.pumpAndSettle();

      // Prueba validaciones de Laravel en el formulario.
      await tester.tap(find.text('Registrar cosecha'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('cosecha.cantidad')),
        '9999',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cosecha.fecha')),
        '2025-01-01',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Registrar cosecha'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar cosecha'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar registro'));
      await tester.pumpAndSettle();

      expect(
        find.text('La cantidad supera el límite permitido para el lote.'),
        findsOneWidget,
      );
      expect(
        find.text('La fecha de cosecha no puede ser anterior a la siembra.'),
        findsOneWidget,
      );
    },
  );
}
