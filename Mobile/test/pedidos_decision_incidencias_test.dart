import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/models/incidente_models.dart';
import 'package:agrofusion_mobile/models/pedido_models.dart';
import 'package:agrofusion_mobile/screens/modules/incidente_form_screen.dart';
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

  testWidgets(
    'Permite rechazar un pedido exigiendo el motivo obligatorio y muestra el rechazo registrado',
    (tester) async {
      await storage.saveToken('1|decision-reject');
      var postCalls = 0;
      Map<String, dynamic>? sentBody;

      final pedidoRechazado = {
        ...pedidoPendiente,
        'estado': 'rechazado',
        'motivo_rechazo': 'Sin stock disponible en almacén',
        'decision': {
          'accion': 'rechazar',
          'estado_resultante': 'rechazado',
          'motivo': 'Sin stock disponible en almacén',
          'usuarioid': 30,
          'fecha': '2026-11-22T01:55:00Z',
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
            postCalls++;
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return jsonResponse({'data': pedidoRechazado});
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

      final rejectBtn = find.byKey(const ValueKey('pedido.accion.rechazar'));
      await tester.ensureVisible(rejectBtn);
      await tester.pumpAndSettle();
      await tester.tap(rejectBtn);
      await tester.pumpAndSettle();

      // Intento sin motivo -> bloqueado en validación local.
      await tester.tap(find.byKey(const ValueKey('pedido.confirmar_rechazo')));
      await tester.pumpAndSettle();
      expect(find.text('Indica el motivo del rechazo.'), findsOneWidget);
      expect(postCalls, 0);

      // Ingresa motivo obligatorio y confirma.
      await tester.enterText(
        find.byKey(const ValueKey('pedido.motivo_rechazo_input')),
        'Sin stock disponible en almacén',
      );
      await tester.tap(find.byKey(const ValueKey('pedido.confirmar_rechazo')));
      await tester.pumpAndSettle();

      expect(postCalls, 1);
      expect(sentBody, {
        'accion': 'rechazar',
        'motivo_rechazo': 'Sin stock disponible en almacén',
      });
      final historial = find.byKey(const ValueKey('pedido.historial'));
      expect(
        find.descendant(of: historial, matching: find.text('Rechazado')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: historial,
          matching: find.text('Sin stock disponible en almacén'),
        ),
        findsOneWidget,
      );
      expect(rejectBtn, findsNothing);
    },
  );

  testWidgets(
    'Gestiona rechazos 403 de permisos desde Laravel ofreciendo actualizar permisos y estado',
    (tester) async {
      await storage.saveToken('1|decision-403');
      var refreshedPermissions = 0;

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
            return jsonResponse({
              'message':
                  'No tienes facultad operativa sobre el almacén de este pedido.',
            }, 403);
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
            onRefreshPermissions: () => refreshedPermissions++,
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

      expect(
        find.text(
          'No tienes facultad operativa sobre el almacén de este pedido.',
        ),
        findsOneWidget,
      );
      final refreshPerms = find.byKey(
        const ValueKey('pedido.refrescar_permisos'),
      );
      expect(refreshPerms, findsOneWidget);
      await tester.ensureVisible(refreshPerms);
      await tester.pumpAndSettle();
      await tester.tap(refreshPerms);
      await tester.pumpAndSettle();
      expect(refreshedPermissions, 1);
    },
  );

  testWidgets(
    'Permite reportar una incidencia vinculada al pedido enviando los datos al servidor',
    (tester) async {
      await storage.saveToken('1|incidente-create');
      Map<String, dynamic>? sentBody;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/pedidos-distribucion/120' &&
              request.method == 'GET') {
            return jsonResponse({'data': pedidoPendiente});
          }
          if (request.url.path == '/api/incidentes' &&
              request.method == 'POST') {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return jsonResponse({
              'incidenteenvioid': 77,
              'tipo': sentBody?['tipo'],
              'descripcion': sentBody?['descripcion'],
              'estado': 'abierto',
              'seguimiento': 'Pendiente de resolución',
              'afectado_referencia': 'Pedido de distribución #120',
            }, 201);
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (settings) {
            if (settings.name == '/modules/incidentes/nuevo') {
              return MaterialPageRoute<IncidenteRecord?>(
                settings: settings,
                builder: (_) => IncidenteFormScreen(
                  args: settings.arguments as IncidenteFormArgs,
                  user: mayoristaUser,
                  service: ModuleService(api),
                  onRefreshPermissions: () {},
                ),
              );
            }
            return null;
          },
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

      final reportBtn = find.byKey(
        const ValueKey('pedido.reportar_incidencia'),
      );
      await tester.ensureVisible(reportBtn);
      await tester.pumpAndSettle();
      await tester.tap(reportBtn);
      await tester.pumpAndSettle();

      expect(find.text('PDV-2026-120 (Distribución)'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('incidente.tipo')),
        'Empaque dañado',
      );
      await tester.enterText(
        find.byKey(const ValueKey('incidente.descripcion')),
        'Dos cajas llegaron golpeadas en la descarga.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('incidente.responsable')),
        '30',
      );

      final saveBtn = find.byKey(const ValueKey('incidente.guardar'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(sentBody, {
        'afectado_tipo': 'pedido_distribucion',
        'afectado_id': 120,
        'tipo': 'Empaque dañado',
        'descripcion': 'Dos cajas llegaron golpeadas en la descarga.',
        'responsable_usuarioid': 30,
      });
      expect(
        find.text('Incidencia #77 reportada correctamente.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Permite consultar si la incidencia está pendiente o resuelta y la explicación de su solución',
    (tester) async {
      await storage.saveToken('1|incidente-view');

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/pedidos-distribucion/120' &&
              request.method == 'GET') {
            return jsonResponse({'data': pedidoPendiente});
          }
          if (request.url.path == '/api/incidentes' &&
              request.method == 'GET') {
            expect(
              request.url.queryParameters['afectado_tipo'],
              'pedido_distribucion',
            );
            expect(request.url.queryParameters['afectado_id'], '120');
            return jsonResponse({
              'data': [
                {
                  'incidenteenvioid': 77,
                  'tipo': 'Demora en transporte',
                  'descripcion': 'Tráfico en carretera principal.',
                  'estado': 'abierto',
                  'seguimiento': 'Pendiente de resolución',
                  'responsable_nombre': 'Diego Rojas',
                  'nota_resolucion': null,
                  'fecha_resolucion': null,
                },
                {
                  'incidenteenvioid': 78,
                  'tipo': 'Empaque dañado',
                  'descripcion': 'Dos cajas golpeadas.',
                  'estado': 'resuelto',
                  'seguimiento': 'Resuelta',
                  'responsable_nombre': 'Diego Rojas',
                  'nota_resolucion':
                      'Se repusieron las dos cajas dañadas en el siguiente despacho.',
                  'resuelto_por': {'usuarioid': 30, 'nombre': 'Diego Rojas'},
                  'fecha_resolucion': '2026-11-22T02:00:00Z',
                },
              ],
              'meta': {'current_page': 1, 'last_page': 1},
            });
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

      expect(find.text('Incidencias vinculadas'), findsOneWidget);
      final inc77 = find.byKey(const ValueKey('incidente.item.77'));
      expect(
        find.descendant(
          of: inc77,
          matching: find.text('Pendiente de resolución'),
        ),
        findsOneWidget,
      );

      final inc78 = find.byKey(const ValueKey('incidente.item.78'));
      expect(
        find.descendant(of: inc78, matching: find.text('Resuelta')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inc78,
          matching: find.text(
            'Se repusieron las dos cajas dañadas en el siguiente despacho.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inc78, matching: find.text('2026-11-22T02:00:00Z')),
        findsOneWidget,
      );
    },
  );
}
