import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/models/pedido_models.dart';
import 'package:agrofusion_mobile/models/qr_envio_models.dart';
import 'package:agrofusion_mobile/screens/modules/envio_qr_detail_screen.dart';
import 'package:agrofusion_mobile/screens/modules/pedido_detail_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();

  const minoristaUser = AuthUser(
    id: 40,
    name: 'Lucía',
    lastName: 'Mendoza',
    email: 'lucia@example.test',
    roles: ['minorista'],
    permissions: {
      'pedidos_distribucion.view',
      'pedidos_distribucion.update',
      'inventario.view',
    },
  );

  const validQrResponse = {
    'data': {
      'recepcion_id': 12,
      'utilizado': false,
      'puede_confirmar': true,
      'envio': {
        'id': 45,
        'tipo': 'distribucion',
        'referencia': 'RUTA-045',
        'estado': 'en_ruta',
        'destinos': [
          {'id': 5, 'nombre': 'Tienda Central', 'direccion': 'Av. América 123'},
        ],
        'lineas': [
          {
            'id': 101,
            'pedido_id': 120,
            'pedido': 'PDV-2026-120',
            'producto': 'Hojuelas de Papa',
            'presentacion': 'Bolsa 500 g',
            'cantidad_enviada': '24.000000',
            'unidad': 'bolsas',
          },
        ],
        'fechas': {
          'salida': '2026-11-21T10:00:00Z',
          'llegada_confirmada': null,
        },
        'recepciones': [],
      },
    },
  };

  const comprobanteResponse = {
    'data': {
      'id': 12,
      'firmante': {'id': 40, 'nombre': 'Lucía Mendoza'},
      'fecha': '2026-11-22T01:15:00Z',
      'firma_url': 'https://example.test/api/recepciones-envio/12/firma',
      'comprobante_url':
          'https://example.test/api/recepciones-envio/12/comprobante',
      'lineas': [
        {
          'id': 101,
          'producto': 'Hojuelas de Papa',
          'cantidad_enviada': '24.000000',
          'cantidad_recibida': '24.000000',
          'unidad': 'bolsas',
        },
      ],
    },
  };

  const pedidoEntregadoResponse = {
    'data': {
      'tipo': 'distribucion',
      'id': 120,
      'numero_solicitud': 'PDV-2026-120',
      'estado': 'entregado',
      'fecha': '2026-11-20T09:00:00Z',
      'fecha_entrega_deseada': '2026-11-22',
      'fecha_aceptacion': '2026-11-20T11:00:00Z',
      'fecha_envio': '2026-11-21T10:00:00Z',
      'fecha_recepcion': '2026-11-22T01:15:00Z',
      'destino': {'puntoventaid': 5, 'nombre': 'Tienda Central'},
      'acciones_disponibles': [],
      'detalles': [
        {
          'id': 101,
          'insumoid': 90,
          'producto': 'Hojuelas de Papa',
          'presentacion': 'Bolsa 500 g',
          'cantidad': '24.000000',
          'unidad': 'bolsas',
          'cantidad_kg': '12.000000',
        },
      ],
    },
  };

  const fakeSignature =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Después de una entrega confirmada vuelve a consultar el estado actualizado del pedido',
    (tester) async {
      await storage.saveToken('1|post-entrega');
      var pedidoGetCalls = 0;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/envios/distribucion/45/recepcion' &&
              request.method == 'POST') {
            return jsonResponse(comprobanteResponse, 201);
          }
          if (request.url.path == '/api/pedidos-distribucion/120' &&
              request.method == 'GET') {
            pedidoGetCalls++;
            return jsonResponse(pedidoEntregadoResponse);
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      final resolution = QrResolucionResult.fromJson(
        validQrResponse,
        codigo: 'QR-POST-45',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EnvioQrDetailScreen(
            tipo: EnvioTipo.distribucion,
            envioId: 45,
            user: minoristaUser,
            service: ModuleService(api),
            onRefreshPermissions: () {},
            initialResolution: resolution,
            signatureExporter: () async => fakeSignature,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pad = find.byKey(const ValueKey('recepcion_envio.firma_pad'));
      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      await tester.drag(pad, const Offset(80, 30));
      await tester.pumpAndSettle();

      final submitBtn = find.byKey(const ValueKey('recepcion_envio.confirmar'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar recepción'),
      );
      await tester.pumpAndSettle();

      expect(pedidoGetCalls, 1);
      expect(find.text('Estado actualizado del pedido'), findsOneWidget);
      final pedidoCard = find.byKey(
        const ValueKey('recepcion_envio.pedido_actualizado.120'),
      );
      expect(pedidoCard, findsOneWidget);
      expect(
        find.descendant(of: pedidoCard, matching: find.text('PDV-2026-120')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pedidoCard, matching: find.text('Entregado')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('recepcion_envio.ver_pedido.120')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Actualiza las cantidades disponibles afectadas por la operación tras confirmar',
    (tester) async {
      await storage.saveToken('1|post-entrega-stock');
      var existenciasCalls = 0;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/envios/distribucion/45/recepcion' &&
              request.method == 'POST') {
            return jsonResponse(comprobanteResponse, 201);
          }
          if (request.url.path == '/api/pedidos-distribucion/120' &&
              request.method == 'GET') {
            return jsonResponse(pedidoEntregadoResponse);
          }
          if (request.url.path == '/api/almacenes' && request.method == 'GET') {
            return jsonResponse({
              'data': [
                {'almacenid': 5, 'nombre': 'Almacén PDV Central'},
              ],
            });
          }
          if (request.url.path == '/api/almacenes/5/existencias' &&
              request.method == 'GET') {
            existenciasCalls++;
            return jsonResponse({
              'data': [
                {
                  'insumoid': 90,
                  'nombre': 'Hojuelas de Papa',
                  'unidad': 'bolsas',
                  'cantidad_fisica': '44.000000',
                  'cantidad_disponible': '44.000000',
                  'cantidad_vencida': '0',
                  'cantidad_bloqueada': '0',
                  'cantidad_reservada': '0',
                  'cantidad_sin_partida': '0',
                  'existencias_bajas': false,
                  'partidas': [],
                },
              ],
              'meta': {'current_page': 1, 'last_page': 1},
            });
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      final resolution = QrResolucionResult.fromJson(
        validQrResponse,
        codigo: 'QR-STOCK-45',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EnvioQrDetailScreen(
            tipo: EnvioTipo.distribucion,
            envioId: 45,
            user: minoristaUser,
            service: ModuleService(api),
            onRefreshPermissions: () {},
            initialResolution: resolution,
            signatureExporter: () async => fakeSignature,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pad = find.byKey(const ValueKey('recepcion_envio.firma_pad'));
      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      await tester.drag(pad, const Offset(80, 30));
      await tester.pumpAndSettle();

      final submitBtn = find.byKey(const ValueKey('recepcion_envio.confirmar'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar recepción'),
      );
      await tester.pumpAndSettle();

      expect(existenciasCalls, 1);
      expect(find.text('Existencias actualizadas'), findsOneWidget);
      final stockBox = find.byKey(
        const ValueKey('recepcion_envio.existencias'),
      );
      expect(stockBox, findsOneWidget);
      expect(
        find.descendant(
          of: stockBox,
          matching: find.text('Hojuelas de Papa · Almacén PDV Central'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stockBox,
          matching: find.text('Disponible: 44 bolsas'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Muestra el comprobante correspondiente a la recepción al consultarlo desde el envío',
    (tester) async {
      await storage.saveToken('1|post-entrega-comp');

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/envios/distribucion/45' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': {
                'id': 45,
                'tipo': 'distribucion',
                'referencia': 'RUTA-045',
                'estado': 'completada',
                'destinos': [
                  {'id': 5, 'nombre': 'Tienda Central'},
                ],
                'lineas': [
                  {
                    'id': 101,
                    'pedido_id': 120,
                    'pedido': 'PDV-2026-120',
                    'producto': 'Hojuelas de Papa',
                    'cantidad_enviada': '24.000000',
                    'unidad': 'bolsas',
                  },
                ],
                'fechas': {'salida': '2026-11-21T10:00:00Z'},
                'recepciones': [
                  {'id': 12, 'fecha': '2026-11-22T01:15:00Z'},
                ],
              },
            });
          }
          if (request.url.path == '/api/recepciones-envio/12' &&
              request.method == 'GET') {
            return jsonResponse(comprobanteResponse);
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EnvioQrDetailScreen(
            tipo: EnvioTipo.distribucion,
            envioId: 45,
            user: minoristaUser,
            service: ModuleService(api),
            onRefreshPermissions: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final verBtn = find.byKey(const ValueKey('envio_qr.ver_comprobante.12'));
      await tester.ensureVisible(verBtn);
      await tester.pumpAndSettle();
      await tester.tap(verBtn);
      await tester.pumpAndSettle();

      final compCard = find.byKey(
        const ValueKey('recepcion_envio.comprobante'),
      );
      expect(compCard, findsOneWidget);
      expect(
        find.descendant(of: compCard, matching: find.text('Recepción #12')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: compCard, matching: find.text('Lucía Mendoza')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: compCard,
          matching: find.text('Registrada y verificada'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: compCard,
          matching: find.text('Disponible en el servidor'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Al volver al pedido tras confirmar la entrega se recupera su historial actualizado',
    (tester) async {
      await storage.saveToken('1|post-entrega-hist');
      final updates = ValueNotifier<int>(0);
      addTearDown(updates.dispose);
      var delivered = false;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/pedidos-distribucion/120' &&
              request.method == 'GET') {
            if (!delivered) {
              return jsonResponse({
                'data': {
                  ...(pedidoEntregadoResponse['data'] as Map<String, dynamic>),
                  'estado': 'confirmado',
                  'fecha_recepcion': null,
                },
              });
            }
            return jsonResponse(pedidoEntregadoResponse);
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PedidoDetailScreen(
            tipo: PedidoTipo.distribucion,
            pedidoId: 120,
            user: minoristaUser,
            service: ModuleService(api),
            onRefreshPermissions: () {},
            updates: updates,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final historial = find.byKey(const ValueKey('pedido.historial'));
      expect(
        find.descendant(of: historial, matching: find.text('Confirmado')),
        findsOneWidget,
      );
      expect(find.text('2026-11-22T01:15:00Z'), findsNothing);

      // Se confirma la entrega y se notifica la actualización al volver al pedido.
      delivered = true;
      updates.value++;
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: historial, matching: find.text('Entregado')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historial,
          matching: find.text('2026-11-22T01:15:00Z'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Reintentar una consulta no vuelve a ejecutar la entrega ni modifica sus cantidades',
    (tester) async {
      await storage.saveToken('1|post-entrega-idempotent');
      var postCalls = 0;
      var getEnvioCalls = 0;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/envios/distribucion/45/recepcion' &&
              request.method == 'POST') {
            postCalls++;
            return jsonResponse(comprobanteResponse, 201);
          }
          if (request.url.path == '/api/envios/distribucion/45' &&
              request.method == 'GET') {
            getEnvioCalls++;
            if (getEnvioCalls == 1) {
              return jsonResponse({'message': 'Error temporal'}, 500);
            }
            return jsonResponse({
              'data': {
                ...(validQrResponse['data'] as Map<String, dynamic>)['envio']
                    as Map<String, dynamic>,
                'estado': 'completada',
                'recepciones': [
                  {'id': 12, 'fecha': '2026-11-22T01:15:00Z'},
                ],
              },
            });
          }
          if (request.url.path == '/api/recepciones-envio/12' &&
              request.method == 'GET') {
            return jsonResponse(comprobanteResponse);
          }
          if (request.url.path == '/api/pedidos-distribucion/120' &&
              request.method == 'GET') {
            return jsonResponse(pedidoEntregadoResponse);
          }
          if (request.url.path == '/api/almacenes' && request.method == 'GET') {
            return jsonResponse({
              'data': [
                {'almacenid': 5, 'nombre': 'Almacén PDV Central'},
              ],
            });
          }
          if (request.url.path == '/api/almacenes/5/existencias' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': [
                {
                  'insumoid': 90,
                  'nombre': 'Hojuelas de Papa',
                  'unidad': 'bolsas',
                  'cantidad_fisica': '44.000000',
                  'cantidad_disponible': '44.000000',
                  'partidas': [],
                },
              ],
              'meta': {'current_page': 1, 'last_page': 1},
            });
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      final resolution = QrResolucionResult.fromJson(
        validQrResponse,
        codigo: 'QR-IDEM-45',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EnvioQrDetailScreen(
            tipo: EnvioTipo.distribucion,
            envioId: 45,
            user: minoristaUser,
            service: ModuleService(api),
            onRefreshPermissions: () {},
            initialResolution: resolution,
            signatureExporter: () async => fakeSignature,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pad = find.byKey(const ValueKey('recepcion_envio.firma_pad'));
      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      await tester.drag(pad, const Offset(80, 30));
      await tester.pumpAndSettle();

      final submitBtn = find.byKey(const ValueKey('recepcion_envio.confirmar'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar recepción'),
      );
      await tester.pumpAndSettle();

      expect(postCalls, 1);

      // Actualización falla con 500 y se reintenta la consulta.
      await tester.tap(find.byKey(const ValueKey('envio_qr.actualizar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(postCalls, 1);
      expect(getEnvioCalls, 2);
      expect(
        find.text('Recibido: 24 bolsas (enviado: 24 bolsas)'),
        findsOneWidget,
      );
      expect(find.text('Disponible: 44 bolsas'), findsOneWidget);
    },
  );

  testWidgets(
    'El estado, las existencias y el comprobante coinciden de extremo a extremo con los datos de Laravel',
    (tester) async {
      await storage.saveToken('1|post-entrega-e2e');

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/envios/distribucion/45/recepcion' &&
              request.method == 'POST') {
            return jsonResponse(comprobanteResponse, 201);
          }
          if (request.url.path == '/api/pedidos-distribucion/120' &&
              request.method == 'GET') {
            return jsonResponse(pedidoEntregadoResponse);
          }
          if (request.url.path == '/api/almacenes' && request.method == 'GET') {
            return jsonResponse({
              'data': [
                {'almacenid': 5, 'nombre': 'Almacén PDV Central'},
              ],
            });
          }
          if (request.url.path == '/api/almacenes/5/existencias' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': [
                {
                  'insumoid': 90,
                  'nombre': 'Hojuelas de Papa',
                  'unidad': 'bolsas',
                  'cantidad_fisica': '44.000000',
                  'cantidad_disponible': '44.000000',
                  'partidas': [],
                },
              ],
              'meta': {'current_page': 1, 'last_page': 1},
            });
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      final resolution = QrResolucionResult.fromJson(
        validQrResponse,
        codigo: 'QR-E2E-45',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (settings) {
            if (settings.name == '/modules/pedidos/distribucion/120') {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => PedidoDetailScreen(
                  tipo: PedidoTipo.distribucion,
                  pedidoId: 120,
                  user: minoristaUser,
                  service: ModuleService(api),
                  onRefreshPermissions: () {},
                ),
              );
            }
            return null;
          },
          home: EnvioQrDetailScreen(
            tipo: EnvioTipo.distribucion,
            envioId: 45,
            user: minoristaUser,
            service: ModuleService(api),
            onRefreshPermissions: () {},
            initialResolution: resolution,
            signatureExporter: () async => fakeSignature,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pad = find.byKey(const ValueKey('recepcion_envio.firma_pad'));
      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      await tester.drag(pad, const Offset(80, 30));
      await tester.pumpAndSettle();

      final submitBtn = find.byKey(const ValueKey('recepcion_envio.confirmar'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar recepción'),
      );
      await tester.pumpAndSettle();

      // Comprobante, pedido y existencias coinciden con Laravel.
      expect(find.text('Recepción #12'), findsOneWidget);
      expect(find.text('Disponible: 44 bolsas'), findsOneWidget);
      expect(find.text('Entregado'), findsOneWidget);

      // Abre el historial completo del pedido desde la tarjeta actualizada.
      final verPedidoBtn = find.byKey(
        const ValueKey('recepcion_envio.ver_pedido.120'),
      );
      await tester.ensureVisible(verPedidoBtn);
      await tester.pumpAndSettle();
      await tester.tap(verPedidoBtn);
      await tester.pumpAndSettle();

      expect(find.text('PDV-2026-120'), findsOneWidget);
      expect(find.text('Estado e historial del pedido'), findsOneWidget);
      expect(find.text('2026-11-22T01:15:00Z'), findsOneWidget);
      expect(find.text('24 bolsas'), findsOneWidget);
      expect(find.text('12 kg'), findsOneWidget);
    },
  );
}
