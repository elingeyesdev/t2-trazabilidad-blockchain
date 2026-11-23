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

  const jefeAgricolaProfile = {
    'usuarioid': 30,
    'nombre': 'Andre',
    'apellido': 'Romero',
    'email': 'andre@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 2, 'name': 'jefe_agricultor'},
    ],
    'permissions': [
      'pedidos.view',
      'pedidos.create',
      'pedidos.update',
      'asignaciones.view',
    ],
  };

  const agricolaFormPayload = {
    'data': {
      'tipo': 'agricola',
      'almacenes_origen': [
        {
          'id': 14,
          'nombre': 'Almacen Norte',
          'ubicacion': 'Calle Río Cuchi · GPS -17.75304, -63.16598',
          'direccion': 'Calle Río Cuchi, Norte Interno',
          'lat': -17.75304,
          'lng': -63.16598,
        },
      ],
      'almacenes_destino': [
        {
          'id': 3,
          'nombre': 'Planta Industrial Norte',
          'ubicacion': 'Parque Industrial',
          'direccion': 'Av. San Aurelio, Santa Cruz',
          'lat': -17.8025,
          'lng': -63.1458,
        },
      ],
      'productos': [
        {
          'producto_ref': 'cosecha:25',
          'tipo': 'cosecha',
          'label': 'Tomate — Semilla de Tomate - Lote 001',
          'almacenid': 14,
          'almacen_nombre': 'Almacen Norte',
          'stock_kg': 1240,
          'unidad': 'kg',
          'calibre_default_id': 27,
          'calibres': [
            {
              'id': 27,
              'id_producto': 96,
              'nombre': 'Mediano (120-130 g)',
              'conteo_por_empaque': 184,
              'peso_promedio_kg': 0.125,
              'id_tipo_empaque': 1,
              'tipo_empaque': 'Caja de cartón',
            },
          ],
          'partidas': [],
        },
      ],
      'tipos_empaque': [
        {'id': 1, 'nombre': 'Caja de cartón'},
        {'id': 4, 'nombre': 'Saco'},
      ],
      'transportistas': [
        {
          'id': 5,
          'nombre': 'Carlos Mamani',
          'licencias': ['C'],
          'vehiculo_default_id': 1,
          'vehiculos_compatibles': [1, 2],
        },
      ],
      'vehiculos': [
        {
          'id': 1,
          'placa': 'SCZ-MOD-01',
          'marca': 'Volvo',
          'modelo': 'FH',
          'tipo_vehiculo': 'Camión grande',
          'capacidad_kg': 10000,
          'capacidad_m3': 40,
          'licencia_requerida': 'C',
          'transporte_principal': 'Multitemperatura',
        },
        {
          'id': 2,
          'placa': 'SCZ-MOD-02',
          'marca': 'Toyota',
          'modelo': 'Hilux',
          'tipo_vehiculo': 'Camioneta',
          'capacidad_kg': 1500,
          'capacidad_m3': 8,
          'licencia_requerida': 'C',
          'transporte_principal': 'Carga general',
        },
      ],
    },
  };

  const createdAgricola = {
    'tipo': 'agricola',
    'id': 71,
    'numero_solicitud': 'PED-20261123-0001',
    'estado': 'sin asignacion',
    'fecha': '2026-11-23T02:00:00Z',
    'fecha_entrega_deseada': '2026-11-24',
    'origen': {
      'direccion': 'Almacen Norte · Calle Río Cuchi, Norte Interno',
      'latitud': -17.75304,
      'longitud': -63.16598,
    },
    'destino': {
      'direccion': 'Planta Industrial Norte · Av. San Aurelio, Santa Cruz',
      'latitud': -17.8025,
      'longitud': -63.1458,
    },
    'envio': {
      'id': 58,
      'externo_envio_id': 'PED-20261123-0001',
      'estado': 'pendiente',
      'transportista_usuarioid': 5,
      'transportista_nombre': 'Carlos Mamani',
      'vehiculo_placa': 'SCZ-MOD-01',
      'costo_bs': 24,
      'fecha_recepcion_planta': null,
    },
    'acciones_disponibles': ['aceptar', 'rechazar'],
    'detalles': [
      {
        'id': 901,
        'producto_ref': 'cosecha:25',
        'producto': 'Tomate',
        'presentacion': 'Mediano (120-130 g)',
        'cantidad': '500.000000',
        'unidad': 'kg',
        'cantidad_kg': '500.000000',
        'almacen_origenid': 14,
      },
    ],
  };

  http.Response jsonResponse(Object? value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Jefe agricultor crea un envío agrícola completo desde móvil con almacén, producto, empaque, chofer, vehículo y costo',
    (tester) async {
      await storage.saveToken('1|jefe-envio');
      Map<String, dynamic>? sentBody;
      var capacidadCalls = 0;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse(jefeAgricolaProfile);
          }
          if (request.url.path == '/api/pedidos-agricolas' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': sentBody == null ? [] : [createdAgricola],
              'meta': {'current_page': 1, 'last_page': 1},
            });
          }
          if (request.url.path == '/api/pedidos-agricolas/formulario' &&
              request.method == 'GET') {
            return jsonResponse(agricolaFormPayload);
          }
          if (request.url.path == '/api/pedidos-agricolas/calcular-costo' &&
              request.method == 'POST') {
            return jsonResponse({
              'data': {
                'costo_bs': 24,
                'distancia_km': 6,
                'paradas': 2,
                'detalle': 'Base Bs 24 (6 km, 2 paradas)',
                'lluvia': false,
              },
            });
          }
          if (request.url.path == '/api/pedidos-agricolas/validar-capacidad' &&
              request.method == 'POST') {
            capacidadCalls++;
            return jsonResponse({
              'data': {
                'ok': true,
                'mensaje': '',
                'capacidad_kg': 10000,
                'capacidad_m3': 40,
                'peso_kg': 500,
                'volumen_m3': 2.5,
                'porcentaje_peso': 5.0,
                'porcentaje_volumen': 6.3,
                'vehiculo': 'SCZ-MOD-01',
              },
            });
          }
          if (request.url.path == '/api/pedidos-agricolas' &&
              request.method == 'POST') {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return jsonResponse({'data': createdAgricola}, 201);
          }
          if (request.url.path == '/api/pedidos-agricolas/71' &&
              request.method == 'GET') {
            return jsonResponse({'data': createdAgricola});
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(AgroFusionApp(apiClient: api));
      await tester.pumpAndSettle();

      // Abre Pedidos desde accesos rápidos (o Trabajo) y entra directo a PedidosScreen.
      await tester.ensureVisible(find.text('Pedidos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedidos'));
      await tester.pumpAndSettle();

      // El botón Nuevo envío está visible para jefe_agricultor.
      expect(find.byKey(const ValueKey('pedidos.crear_btn')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pedidos.crear_btn')));
      await tester.pumpAndSettle();

      // Almacén origen, destino, producto único, chofer único, vehículo y costo se preseleccionan automáticamente.
      expect(find.text('Almacen Norte · Calle Río Cuchi, Norte Interno'), findsOneWidget);
      expect(find.text('Planta Industrial Norte'), findsAtLeastNWidgets(1));
      expect(find.text('Base Bs 24 (6 km, 2 paradas)'), findsOneWidget);

      // Ingresa cantidad en kg y valida capacidad.
      final qtyField = find.byKey(const ValueKey('pedido.linea.0.cantidad'));
      await tester.ensureVisible(qtyField);
      await tester.pumpAndSettle();
      await tester.enterText(qtyField, '500');
      await tester.pumpAndSettle();

      expect(capacidadCalls, greaterThan(0));
      expect(find.byKey(const ValueKey('pedido.capacidad_preview')), findsOneWidget);
      expect(find.text('Ocupación del vehículo SCZ-MOD-01'), findsOneWidget);

      // Confirma y crea el envío.
      final saveBtn = find.byKey(const ValueKey('pedido.guardar'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(sentBody, isNotNull);
      expect(sentBody!['origen_almacenid'], 14);
      expect(sentBody!['transportista_usuarioid'], 5);
      expect(sentBody!['vehiculoid'], 1);
      expect(sentBody!['costo_bs'], 24);
      final detalles = sentBody!['detalles'] as List;
      expect(detalles, hasLength(1));
      expect(detalles.first['producto_ref'], 'cosecha:25');
      expect(detalles.first['cantidad'], '500.0');
      expect(detalles.first['catalogotamanoconteoid'], 27);
      expect(
        detalles.first['observaciones'],
        contains('@carga:500 kg · Caja de cartón · Mediano (120-130 g)@'),
      );

      // Al abrir el detalle muestra el envío con chofer, vehículo, costo y acciones disponibles.
      expect(find.text('PED-20261123-0001'), findsAtLeastNWidgets(1));
      expect(find.byKey(const ValueKey('pedido.transporte')), findsOneWidget);
      expect(find.text('Carlos Mamani'), findsOneWidget);
      expect(find.text('SCZ-MOD-01'), findsOneWidget);
      expect(find.text('Bs 24'), findsOneWidget);
      expect(find.byKey(const ValueKey('pedido.accion.aceptar')), findsOneWidget);
    },
  );
}
