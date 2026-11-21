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

  const gestorProfile = {
    'usuarioid': 12,
    'nombre': 'Carlos',
    'apellido': 'Mendoza',
    'email': 'carlos@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 2, 'name': 'jefe_agricultor'},
    ],
    'permissions': ['inventario.view', 'almacen.movimientos.view'],
  };

  const almacenesPayload = [
    {
      'almacenid': 4,
      'nombre': 'Almacén Norte',
      'ubicacion': 'Sector A',
      'capacidad': 5000,
      'ambito': 'agricola',
      'activo': true,
    },
    {
      'almacenid': 5,
      'nombre': 'Almacén Sur',
      'ubicacion': 'Sector B',
      'capacidad': 3000,
      'ambito': 'agricola',
      'activo': true,
    },
  ];

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
    await storage.saveToken('1|alertas-test');
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
    'Distingue vencidos, próximos a vencer y existencias bajas con fecha/producto/almacén/cantidad, filtra por almacén y actualiza desde Laravel',
    (tester) async {
      var lowStockResolved = false;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(gestorProfile);
        if (request.url.path == '/api/almacenes' && request.method == 'GET') {
          return jsonResponse(almacenesPayload);
        }
        if (request.url.path == '/api/almacenes/4/existencias' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [
              {
                'insumoid': 101,
                'nombre': 'Fungicida Cúprico',
                'unidad': 'L',
                'cantidad_fisica': '12.000000',
                'cantidad_disponible': '7.000000',
                'cantidad_vencida': '5.000000',
                'cantidad_bloqueada': '0.000000',
                'cantidad_reservada': '0.000000',
                'cantidad_sin_partida': '0.000000',
                'minimo': '2.000000',
                'existencias_bajas': false,
                'partidas': [
                  {
                    'materiaprimaloteid': 20,
                    'referencia': 'LOT-VENC-01',
                    'cantidad_fisica': '5.000000',
                    'fecha_vencimiento': '2026-11-10',
                    'vencimiento_estado': 'vencido',
                    'utilizable': false,
                  },
                  {
                    'materiaprimaloteid': 21,
                    'referencia': 'LOT-PROX-02',
                    'cantidad_fisica': '7.000000',
                    'fecha_vencimiento': '2026-11-23',
                    'vencimiento_estado': 'proximo_a_vencer',
                    'utilizable': true,
                  },
                ],
              },
            ],
            'current_page': 1,
            'last_page': 1,
          });
        }
        if (request.url.path == '/api/almacenes/5/existencias' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [
              {
                'insumoid': 202,
                'nombre': 'Semilla Certificada',
                'unidad': 'kg',
                'cantidad_fisica': lowStockResolved ? '30.000000' : '4.000000',
                'cantidad_disponible': lowStockResolved
                    ? '30.000000'
                    : '4.000000',
                'cantidad_vencida': '0.000000',
                'cantidad_bloqueada': '0.000000',
                'cantidad_reservada': '0.000000',
                'cantidad_sin_partida': lowStockResolved
                    ? '30.000000'
                    : '4.000000',
                'minimo': '10.000000',
                'existencias_bajas': !lowStockResolved,
                'partidas': <Map<String, Object?>>[],
              },
            ],
            'current_page': 1,
            'last_page': 1,
          });
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Almacenes'));
      await tester.tap(find.text('Almacenes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver alertas'));
      await tester.pumpAndSettle();

      // Muestra las 3 alertas con texto explícito, fecha, producto, almacén y cantidad.
      expect(find.text('Todas (3)'), findsOneWidget);
      expect(find.text('Vencidos (1)'), findsOneWidget);
      expect(find.text('Próximos a vencer (1)'), findsOneWidget);
      expect(find.text('Existencias bajas (1)'), findsOneWidget);

      expect(find.text('Vencido'), findsOneWidget);
      expect(find.text('Próximo a vencer'), findsOneWidget);
      expect(find.text('Existencias bajas'), findsOneWidget);
      expect(find.text('Almacén: Almacén Norte'), findsNWidgets(2));
      expect(find.text('Almacén: Almacén Sur'), findsOneWidget);
      expect(
        find.text('Cantidad vencida: 5 L · Fecha de vencimiento: 2026-11-10'),
        findsOneWidget,
      );
      expect(
        find.text('Cantidad próxima a vencer: 7 L · Vence el 2026-11-23'),
        findsOneWidget,
      );
      expect(
        find.text('Disponible: 4 kg · Mínimo configurado: 10 kg'),
        findsOneWidget,
      );

      // Filtra por almacén autorizado (Almacén Sur) -> solo muestra Semilla Certificada.
      await tester.tap(find.byKey(const ValueKey('alertas.almacen_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Almacén Sur').last);
      await tester.pumpAndSettle();

      expect(find.text('Semilla Certificada'), findsOneWidget);
      expect(find.text('Fungicida Cúprico'), findsNothing);

      // Al actualizar tras reponer stock en Laravel, desaparece la alerta de stock bajo.
      lowStockResolved = true;
      await tester.tap(find.byTooltip('Actualizar alertas'));
      await tester.pumpAndSettle();

      expect(find.text('Sin alertas en esta vista'), findsOneWidget);
    },
  );
}
