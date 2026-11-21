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

  const minoristaProfile = {
    'usuarioid': 40,
    'nombre': 'Lucía',
    'apellido': 'Mendoza',
    'email': 'lucia@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 8, 'name': 'minorista'},
    ],
    'permissions': [
      'pedidos_distribucion.view',
      'pedidos_distribucion.create',
      'pedidos_distribucion.update',
    ],
  };

  const createdDistribucion = {
    'tipo': 'distribucion',
    'id': 120,
    'numero_solicitud': 'PDV-2026-120',
    'estado': 'pendiente',
    'fecha': '2026-11-21T13:00:00Z',
    'fecha_entrega_deseada': '2026-11-25',
    'creado_por_usuarioid': 40,
    'aceptado_por_usuarioid': null,
    'fecha_aceptacion': null,
    'envio_iniciado_mayorista': false,
    'fecha_confirmacion_minorista': null,
    'fecha_envio': null,
    'fecha_recepcion': null,
    'envio': null,
    'destino': {'puntoventaid': 5, 'nombre': 'Tienda Central'},
    'observaciones': 'Entregar por la mañana',
    'decision': null,
    'motivo_rechazo': null,
    'acciones_disponibles': [],
    'detalles': [
      {
        'id': 801,
        'producto_ref': null,
        'insumoid': 90,
        'materiaprimaloteid': null,
        'producto': 'Hojuelas de Papa',
        'produccionalmacenamientoid': null,
        'presentacionid': 15,
        'catalogotamanoconteoid': null,
        'presentacion': 'Bolsa 500 g',
        'cantidad': '24.000000',
        'unidad': 'bolsas',
        'cantidad_kg': '12.000000',
        'almacen_origenid': 11,
        'inventario_presentacion_loteid': null,
      },
    ],
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
    await storage.saveToken('1|pedidos-test');
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
    'Permite crear un pedido seleccionando productos, presentaciones, cantidades y destino',
    (tester) async {
      Map<String, dynamic>? sentBody;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(minoristaProfile);
        }
        if (request.url.path == '/api/pedidos-distribucion' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': sentBody == null ? [] : [createdDistribucion],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/pedidos-distribucion' &&
            request.method == 'POST') {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({'data': createdDistribucion}, 201);
        }
        if (request.url.path == '/api/pedidos-distribucion/120' &&
            request.method == 'GET') {
          return jsonResponse({'data': createdDistribucion});
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver pedidos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pedidos.crear_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('pedido.destino')), '5');
      await tester.enterText(
        find.byKey(const ValueKey('pedido.fecha_entrega')),
        '2026-11-25',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pedido.linea.0.producto')),
        '90',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pedido.linea.0.presentacion')),
        '15',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pedido.linea.0.cantidad')),
        '24',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pedido.observaciones')),
        'Entregar por la mañana',
      );

      await tester.ensureVisible(find.byKey(const ValueKey('pedido.guardar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pedido.guardar')));
      await tester.pumpAndSettle();

      expect(sentBody, {
        'puntoventaid': 5,
        'fecha_entrega_deseada': '2026-11-25',
        'observaciones': 'Entregar por la mañana',
        'detalles': [
          {'insumoid': 90, 'insumo_presentacionid': 15, 'cantidad': '24'},
        ],
      });
      expect(find.text('PDV-2026-120'), findsOneWidget);
      expect(find.text('Tienda Central (PDV #5)'), findsOneWidget);
      expect(find.text('Hojuelas de Papa · Bolsa 500 g'), findsOneWidget);
      expect(find.text('24 bolsas'), findsOneWidget);
      expect(find.text('12 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'Muestra errores de disponibilidad y validación sin perder los datos del formulario',
    (tester) async {
      var attempts = 0;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(minoristaProfile);
        }
        if (request.url.path == '/api/pedidos-distribucion' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': const <Map<String, Object?>>[],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/pedidos-distribucion' &&
            request.method == 'POST') {
          attempts++;
          if (attempts == 1) {
            return jsonResponse({
              'message': 'No se pudo registrar el pedido.',
              'errors': {
                'detalles': [
                  'Stock insuficiente para Hojuelas de Papa en Almacén #11.',
                ],
                'detalles.0.cantidad': [
                  'La cantidad supera el saldo disponible (10 envases).',
                ],
              },
            }, 422);
          }
          return jsonResponse({'data': createdDistribucion}, 201);
        }
        if (request.url.path == '/api/pedidos-distribucion/120' &&
            request.method == 'GET') {
          return jsonResponse({'data': createdDistribucion});
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver pedidos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pedidos.crear_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('pedido.destino')), '5');
      await tester.enterText(
        find.byKey(const ValueKey('pedido.fecha_entrega')),
        '2026-11-25',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pedido.linea.0.producto')),
        '90',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pedido.linea.0.presentacion')),
        '15',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pedido.linea.0.cantidad')),
        '50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pedido.observaciones')),
        'Pedido urgente',
      );

      await tester.ensureVisible(find.byKey(const ValueKey('pedido.guardar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pedido.guardar')));
      await tester.pumpAndSettle();

      expect(
        find.text('Stock insuficiente para Hojuelas de Papa en Almacén #11.'),
        findsOneWidget,
      );
      expect(
        find.text('La cantidad supera el saldo disponible (10 envases).'),
        findsOneWidget,
      );
      // Todos los datos ingresados se conservan.
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2026-11-25'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('Pedido urgente'), findsOneWidget);

      // Corrige cantidad y reenvía correctamente.
      await tester.ensureVisible(
        find.byKey(const ValueKey('pedido.linea.0.cantidad')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pedido.linea.0.cantidad')),
        '10',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('pedido.guardar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pedido.guardar')));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('PDV-2026-120'), findsOneWidget);
    },
  );

  testWidgets(
    'Permite consultar pedidos agrícolas y de distribución autorizados con filtro de estado',
    (tester) async {
      const dualProfile = {
        'usuarioid': 1,
        'nombre': 'Carlos',
        'apellido': 'Supervisor',
        'email': 'carlos@example.test',
        'activo': true,
        'estado_cuenta': 'aprobado',
        'roles': [
          {'id': 1, 'name': 'admin'},
        ],
        'permissions': ['pedidos.view', 'pedidos_distribucion.view'],
      };

      const agricolaConfirmed = {
        'tipo': 'agricola',
        'id': 7,
        'numero_solicitud': 'PED-AGR-007',
        'estado': 'confirmado',
        'fecha': '2026-11-20T09:00:00Z',
        'fecha_entrega_deseada': '2026-11-22',
        'destino': {
          'latitud': '-17.3895',
          'longitud': '-66.1568',
          'direccion': 'Planta Procesadora Sur',
        },
        'acciones_disponibles': [],
        'detalles': [
          {
            'id': 301,
            'producto': 'Papa Huaycha',
            'cantidad': '150.000000',
            'unidad': 'kg',
            'cantidad_kg': '150.000000',
          },
        ],
      };

      String? lastAgricolaEstado;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(dualProfile);
        }
        if (request.url.path == '/api/pedidos' && request.method == 'GET') {
          return jsonResponse([]);
        }
        if (request.url.path == '/api/pedidos-distribucion' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [createdDistribucion],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/pedidos-agricolas' &&
            request.method == 'GET') {
          lastAgricolaEstado = request.url.queryParameters['estado'];
          return jsonResponse({
            'data': [agricolaConfirmed],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver pedidos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solicitudes y pedidos'));
      await tester.pumpAndSettle();

      // Inicialmente ve Distribución.
      expect(find.text('PDV-2026-120'), findsOneWidget);
      expect(find.text('Destino: Tienda Central (PDV #5)'), findsOneWidget);

      // Cambia a Agrícola y filtra por Confirmado.
      await tester.tap(find.byKey(const ValueKey('pedidos.tipo.agricola')));
      await tester.pumpAndSettle();
      expect(find.text('PED-AGR-007'), findsOneWidget);
      expect(find.text('Destino: Planta Procesadora Sur'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pedidos.estado.confirmado')));
      await tester.pumpAndSettle();
      expect(lastAgricolaEstado, 'confirmado');
      expect(find.text('PED-AGR-007'), findsOneWidget);
    },
  );

  testWidgets(
    'El detalle muestra el estado y el historial completo del pedido',
    (tester) async {
      final detailedPedido = {
        ...createdDistribucion,
        'estado': 'rechazado',
        'fecha_aceptacion': '2026-11-21T14:00:00Z',
        'envio_iniciado_mayorista': true,
        'fecha_confirmacion_minorista': '2026-11-21T14:30:00Z',
        'fecha_envio': '2026-11-21T15:00:00Z',
        'fecha_recepcion': '2026-11-21T17:00:00Z',
        'decision': {
          'accion': 'rechazar',
          'estado_resultante': 'rechazado',
          'motivo': 'Sin disponibilidad en cámara fría',
          'usuarioid': 9,
          'fecha': '2026-11-21T14:15:00Z',
        },
        'motivo_rechazo': 'Sin disponibilidad en cámara fría',
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(minoristaProfile);
        }
        if (request.url.path == '/api/pedidos-distribucion' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [detailedPedido],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/pedidos-distribucion/120' &&
            request.method == 'GET') {
          return jsonResponse({'data': detailedPedido});
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver pedidos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDV-2026-120'));
      await tester.pumpAndSettle();

      expect(find.text('Estado e historial del pedido'), findsOneWidget);
      final historial = find.byKey(const ValueKey('pedido.historial'));
      expect(
        find.descendant(of: historial, matching: find.text('Rechazado')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historial,
          matching: find.text('2026-11-21T13:00:00Z'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historial,
          matching: find.text('2026-11-21T14:00:00Z'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historial,
          matching: find.text('Envío iniciado por mayorista'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historial,
          matching: find.text('Rechazar pedido (2026-11-21T14:15:00Z)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historial,
          matching: find.text('Sin disponibilidad en cámara fría'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Identifica las acciones disponibles según permisos y estado del pedido',
    (tester) async {
      const mayoristaProfile = {
        'usuarioid': 30,
        'nombre': 'Diego',
        'apellido': 'Rojas',
        'email': 'diego@example.test',
        'activo': true,
        'estado_cuenta': 'aprobado',
        'roles': [
          {'id': 7, 'name': 'mayorista'},
        ],
        'permissions': [
          'pedidos_distribucion.view',
          'pedidos_distribucion.update',
        ],
      };

      final pendingWithActions = {
        ...createdDistribucion,
        'acciones_disponibles': ['aceptar', 'rechazar'],
      };

      final closedWithoutActions = {
        ...createdDistribucion,
        'id': 121,
        'numero_solicitud': 'PDV-2026-121',
        'estado': 'entregado',
        'acciones_disponibles': const <String>[],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(mayoristaProfile);
        }
        if (request.url.path == '/api/pedidos-distribucion' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [pendingWithActions, closedWithoutActions],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/pedidos-distribucion/120' &&
            request.method == 'GET') {
          return jsonResponse({'data': pendingWithActions});
        }
        if (request.url.path == '/api/pedidos-distribucion/121' &&
            request.method == 'GET') {
          return jsonResponse({'data': closedWithoutActions});
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver pedidos'));
      await tester.pumpAndSettle();

      // Pedido pendiente con acciones autorizadas.
      await tester.tap(find.text('PDV-2026-120'));
      await tester.pumpAndSettle();

      expect(find.text('Acciones disponibles'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pedido.accion.aceptar')),
        findsOneWidget,
      );
      expect(find.text('Aceptar pedido'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pedido.accion.rechazar')),
        findsOneWidget,
      );
      expect(find.text('Rechazar pedido'), findsOneWidget);

      // Pedido entregado sin acciones disponibles.
      await tester.tap(find.byKey(const ValueKey('pedido.volver')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDV-2026-121'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pedido.sin_acciones')), findsOneWidget);
      expect(find.byKey(const ValueKey('pedido.accion.aceptar')), findsNothing);
    },
  );
}
