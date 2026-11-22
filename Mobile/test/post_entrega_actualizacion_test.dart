import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/models/qr_envio_models.dart';
import 'package:agrofusion_mobile/screens/modules/envio_qr_detail_screen.dart';
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
}
