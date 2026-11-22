import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/models/pedido_models.dart';
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

  const mayoristaUser = AuthUser(
    id: 30,
    name: 'Diego',
    lastName: 'Rojas',
    email: 'diego@example.test',
    roles: ['mayorista'],
    permissions: {
      'pedidos_distribucion.view',
      'pedidos_distribucion.update',
      'incidentes.view',
      'incidentes.create',
    },
  );

  const pedidoPendiente = {
    'tipo': 'distribucion',
    'id': 120,
    'numero_solicitud': 'PDV-2026-120',
    'estado': 'pendiente',
    'fecha': '2026-11-21T10:00:00Z',
    'fecha_entrega_deseada': '2026-11-25',
    'destino': {'puntoventaid': 5, 'nombre': 'Tienda Central'},
    'acciones_disponibles': ['aceptar', 'rechazar'],
    'detalles': [
      {
        'id': 801,
        'insumoid': 90,
        'producto': 'Hojuelas de Papa',
        'presentacion': 'Bolsa 500 g',
        'cantidad': '24.000000',
        'unidad': 'bolsas',
        'cantidad_kg': '12.000000',
      },
    ],
  };

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'El usuario autorizado puede aceptar un pedido y consultar el estado resultante',
    (tester) async {
      await storage.saveToken('1|decision-accept');
      Map<String, dynamic>? sentBody;

      final pedidoConfirmado = {
        ...pedidoPendiente,
        'estado': 'confirmado',
        'fecha_aceptacion': '2026-11-22T01:45:00Z',
        'decision': {
          'accion': 'aceptar',
          'estado_resultante': 'confirmado',
          'motivo': null,
          'usuarioid': 30,
          'fecha': '2026-11-22T01:45:00Z',
        },
        'acciones_disponibles': const <String>[],
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/pedidos-distribucion/120' &&
              request.method == 'GET') {
            return jsonResponse({'data': pedidoPendiente});
          }
          if (request.url.path ==
                  '/api/pedidos-distribucion/120/transiciones' &&
              request.method == 'POST') {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return jsonResponse({'data': pedidoConfirmado});
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
            user: mayoristaUser,
            service: ModuleService(api),
            onRefreshPermissions: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final acceptBtn = find.byKey(const ValueKey('pedido.accion.aceptar'));
      await tester.ensureVisible(acceptBtn);
      await tester.pumpAndSettle();
      await tester.tap(acceptBtn);
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, 'Aceptar pedido').last,
      );
      await tester.pumpAndSettle();

      expect(sentBody, {'accion': 'aceptar'});
      expect(
        find.text('Decisión registrada: estado Confirmado.'),
        findsOneWidget,
      );
      final historial = find.byKey(const ValueKey('pedido.historial'));
      expect(
        find.descendant(of: historial, matching: find.text('Confirmado')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historial,
          matching: find.text('2026-11-22T01:45:00Z'),
        ),
        findsOneWidget,
      );
      expect(acceptBtn, findsNothing);
    },
  );
}
