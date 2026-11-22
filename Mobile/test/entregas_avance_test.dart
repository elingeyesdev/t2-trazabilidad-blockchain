import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/screens/modules/entrega_detail_screen.dart';
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

  const transportistaProfile = {
    'usuarioid': 50,
    'nombre': 'Raúl',
    'apellido': 'Vega',
    'email': 'raul@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 9, 'name': 'transportista'},
    ],
    'permissions': [
      'rutas_multi.view',
      'rutas_multi.update',
      'asignaciones.view',
    ],
  };

  const rutaSummary = {
    'rutamultientregaid': 18,
    'nombre': 'Ruta Valle Alto #18',
    'estado': 'planificada',
    'fecha_salida': '2026-11-21T08:00:00Z',
    'fecha_cierre': null,
    'paradas_count': 2,
  };

  const envioAgricolaRow = {
    'id': 91,
    'tipo': 'agricola',
    'referencia': 'ENV-AGR-091',
    'estado': 'en_transporte_planta',
    'destinos': [
      {'nombre': 'Planta Sur', 'direccion': 'Km 12 Carretera Antigua'},
    ],
    'lineas': [],
    'fechas': {'salida': '2026-11-21T07:30:00Z', 'llegada_confirmada': null},
    'recepciones': [],
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
    await storage.saveToken('1|entregas-test');
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
    'El transportista puede consultar los envíos que le corresponden',
    (tester) async {
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(transportistaProfile);
        }
        if (request.url.path == '/api/asignaciones-multiples' &&
            request.method == 'GET') {
          return jsonResponse({'data': [], 'current_page': 1, 'last_page': 1});
        }
        if (request.url.path == '/api/rutas-multi' && request.method == 'GET') {
          return jsonResponse({
            'data': [rutaSummary],
            'current_page': 1,
            'last_page': 1,
          });
        }
        if (request.url.path == '/api/envios/agricola' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [envioAgricolaRow],
            'meta': {'current_page': 1, 'per_page': 15, 'total': 1},
          });
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver asignaciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mis envíos y entregas'));
      await tester.pumpAndSettle();

      expect(find.text('Ruta Valle Alto #18'), findsOneWidget);
      expect(find.text('Planificada'), findsOneWidget);
      expect(find.text('2 paradas'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('entregas.tab.agricola')));
      await tester.pumpAndSettle();

      expect(find.text('ENV-AGR-091'), findsOneWidget);
      expect(
        find.text('Destino: Planta Sur · Km 12 Carretera Antigua'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'El detalle muestra las paradas en orden, el destino y el estado del envío',
    (tester) async {
      const rutaDetailUnsorted = {
        'rutamultientregaid': 18,
        'nombre': 'Ruta Valle Alto #18',
        'estado': 'en_ruta',
        'fecha_salida': '2026-11-21T08:00:00Z',
        'fecha_cierre': null,
        'paradas': [
          {
            'rutaparadaid': 303,
            'orden': 3,
            'destino': 'Mercado Sur',
            'estado': 'pendiente',
            'externo_envio_id': 'ENV-303',
          },
          {
            'rutaparadaid': 301,
            'orden': 1,
            'destino': 'Planta Procesadora Norte',
            'estado': 'entregada',
            'externo_envio_id': 'ENV-301',
            'pedido': {
              'direccion_texto': 'Av. Blanco Galindo Km 8',
              'latitud': '-17.3935',
              'longitud': '-66.2241',
            },
          },
          {
            'rutaparadaid': 302,
            'orden': 2,
            'destino': 'Tienda Central',
            'estado': 'en_ruta',
            'externo_envio_id': 'ENV-302',
          },
        ],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(transportistaProfile);
        }
        if (request.url.path == '/api/asignaciones-multiples' &&
            request.method == 'GET') {
          return jsonResponse({'data': [], 'current_page': 1, 'last_page': 1});
        }
        if (request.url.path == '/api/rutas-multi' && request.method == 'GET') {
          return jsonResponse({
            'data': [rutaSummary],
            'current_page': 1,
            'last_page': 1,
          });
        }
        if (request.url.path == '/api/rutas-multi/18' &&
            request.method == 'GET') {
          return jsonResponse(rutaDetailUnsorted);
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver asignaciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mis envíos y entregas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ruta Valle Alto #18'));
      await tester.pumpAndSettle();

      expect(find.text('Paradas en orden'), findsOneWidget);
      expect(find.text('Planta Procesadora Norte'), findsOneWidget);
      expect(find.text('Tienda Central'), findsOneWidget);
      expect(find.text('Mercado Sur'), findsOneWidget);

      final y1 = tester
          .getTopLeft(find.byKey(const ValueKey('entrega.parada.1')))
          .dy;
      final y2 = tester
          .getTopLeft(find.byKey(const ValueKey('entrega.parada.2')))
          .dy;
      final y3 = tester
          .getTopLeft(find.byKey(const ValueKey('entrega.parada.3')))
          .dy;
      expect(y1, lessThan(y2));
      expect(y2, lessThan(y3));
    },
  );

  testWidgets(
    'El transportista puede registrar los avances permitidos de su entrega',
    (tester) async {
      var currentEstado = 'planificada';
      final sentEstados = <String>[];

      Map<String, dynamic> buildRuta() => {
        'rutamultientregaid': 18,
        'nombre': 'Ruta Valle Alto #18',
        'estado': currentEstado,
        'fecha_salida': '2026-11-21T08:00:00Z',
        'fecha_cierre': currentEstado == 'completada'
            ? '2026-11-21T16:00:00Z'
            : null,
        'paradas': [
          {
            'rutaparadaid': 301,
            'orden': 1,
            'destino': 'Planta Procesadora Norte',
            'estado': currentEstado == 'completada' ? 'entregada' : 'pendiente',
          },
        ],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(transportistaProfile);
        }
        if (request.url.path == '/api/asignaciones-multiples' &&
            request.method == 'GET') {
          return jsonResponse({'data': [], 'current_page': 1, 'last_page': 1});
        }
        if (request.url.path == '/api/rutas-multi' && request.method == 'GET') {
          return jsonResponse({
            'data': [buildRuta()],
            'current_page': 1,
            'last_page': 1,
          });
        }
        if (request.url.path == '/api/rutas-multi/18' &&
            request.method == 'GET') {
          return jsonResponse(buildRuta());
        }
        if (request.url.path == '/api/rutas-multi/18' &&
            request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          currentEstado = body['estado'] as String;
          sentEstados.add(currentEstado);
          return jsonResponse(buildRuta());
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver asignaciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mis envíos y entregas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ruta Valle Alto #18'));
      await tester.pumpAndSettle();

      // Planificada -> En ruta.
      await tester.tap(find.byKey(const ValueKey('entrega.avanzar.en_ruta')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar ruta').last);
      await tester.pumpAndSettle();

      expect(sentEstados, ['en_ruta']);
      expect(find.text('Avance registrado: En ruta.'), findsOneWidget);

      // En ruta -> Completada.
      await tester.tap(
        find.byKey(const ValueKey('entrega.avanzar.completada')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Finalizar entrega').last,
      );
      await tester.pumpAndSettle();

      expect(sentEstados, ['en_ruta', 'completada']);
      expect(find.text('Avance registrado: Completada.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('entrega.avanzar.completada')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Los errores de cambio de estado y conexión se muestran sin presentar un avance sin confirmar',
    (tester) async {
      var patchCalls = 0;

      const rutaPlanificada = {
        'rutamultientregaid': 18,
        'nombre': 'Ruta Valle Alto #18',
        'estado': 'planificada',
        'fecha_salida': '2026-11-21T08:00:00Z',
        'fecha_cierre': null,
        'paradas': [
          {
            'rutaparadaid': 301,
            'orden': 1,
            'destino': 'Planta Procesadora Norte',
            'estado': 'pendiente',
          },
        ],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(transportistaProfile);
        }
        if (request.url.path == '/api/asignaciones-multiples' &&
            request.method == 'GET') {
          return jsonResponse({'data': [], 'current_page': 1, 'last_page': 1});
        }
        if (request.url.path == '/api/rutas-multi' && request.method == 'GET') {
          return jsonResponse({
            'data': [rutaPlanificada],
            'current_page': 1,
            'last_page': 1,
          });
        }
        if (request.url.path == '/api/rutas-multi/18' &&
            request.method == 'GET') {
          return jsonResponse(rutaPlanificada);
        }
        if (request.url.path == '/api/rutas-multi/18' &&
            request.method == 'PATCH') {
          patchCalls++;
          if (patchCalls == 1) {
            return jsonResponse({
              'message': 'No se puede iniciar la ruta en este estado.',
            }, 409);
          }
          throw http.ClientException('Sin conexión');
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver asignaciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mis envíos y entregas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ruta Valle Alto #18'));
      await tester.pumpAndSettle();

      // 1) Error 409 de cambio de estado.
      await tester.tap(find.byKey(const ValueKey('entrega.avanzar.en_ruta')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar ruta').last);
      await tester.pumpAndSettle();

      expect(
        find.text('No se puede iniciar la ruta en este estado.'),
        findsOneWidget,
      );
      final badge = find.byKey(const ValueKey('entrega.estado_badge'));
      expect(
        find.descendant(of: badge, matching: find.text('Planificada')),
        findsOneWidget,
      );
      expect(find.text('En ruta'), findsNothing);

      // 2) Error de conexión.
      await tester.tap(find.byKey(const ValueKey('entrega.avanzar.en_ruta')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar ruta').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('entrega.update_error')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: badge, matching: find.text('Planificada')),
        findsOneWidget,
      );
      expect(find.text('En ruta'), findsNothing);
    },
  );

  testWidgets(
    'Si hay ubicación disponible permite abrir el destino en una aplicación de mapas externa',
    (tester) async {
      await storage.saveToken('1|entregas-map');
      Uri? launchedUri;

      const rutaWithAndWithoutLocation = {
        'rutamultientregaid': 18,
        'nombre': 'Ruta Valle Alto #18',
        'estado': 'en_ruta',
        'fecha_salida': '2026-11-21T08:00:00Z',
        'paradas': [
          {
            'rutaparadaid': 301,
            'orden': 1,
            'destino': 'Planta Procesadora Norte',
            'estado': 'pendiente',
            'pedido': {
              'direccion_texto': 'Av. Blanco Galindo Km 8',
              'latitud': '-17.3935',
              'longitud': '-66.2241',
            },
          },
          {
            'rutaparadaid': 302,
            'orden': 2,
            'destino': null,
            'estado': 'pendiente',
          },
        ],
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/rutas-multi/18' &&
              request.method == 'GET') {
            return jsonResponse(rutaWithAndWithoutLocation);
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      const user = AuthUser(
        id: 50,
        name: 'Raúl',
        lastName: 'Vega',
        email: 'raul@example.test',
        roles: ['transportista'],
        permissions: {'rutas_multi.view', 'rutas_multi.update'},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EntregaDetailScreen(
            rutaId: 18,
            user: user,
            service: ModuleService(api),
            onRefreshPermissions: () {},
            mapLauncher: (uri) async {
              launchedUri = uri;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('entrega.mapa.1')), findsOneWidget);
      expect(find.byKey(const ValueKey('entrega.mapa.2')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('entrega.mapa.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('entrega.mapa.1')));
      await tester.pumpAndSettle();

      expect(launchedUri, isNotNull);
      expect(launchedUri!.host, 'www.google.com');
      expect(launchedUri!.queryParameters['query'], '-17.3935,-66.2241');
    },
  );

  testWidgets(
    'Al actualizar el detalle y el listado el avance del envío coincide con el registrado en la web',
    (tester) async {
      var detailCalls = 0;

      const initialRuta = {
        'rutamultientregaid': 18,
        'nombre': 'Ruta Valle Alto #18',
        'estado': 'planificada',
        'fecha_salida': '2026-11-21T08:00:00Z',
        'fecha_cierre': null,
        'paradas': [
          {
            'rutaparadaid': 301,
            'orden': 1,
            'destino': 'Planta Procesadora Norte',
            'estado': 'pendiente',
          },
        ],
      };

      const webUpdatedRuta = {
        'rutamultientregaid': 18,
        'nombre': 'Ruta Valle Alto #18',
        'estado': 'completada',
        'fecha_salida': '2026-11-21T08:00:00Z',
        'fecha_cierre': '2026-11-22T09:15:00Z',
        'paradas': [
          {
            'rutaparadaid': 301,
            'orden': 1,
            'destino': 'Planta Procesadora Norte',
            'estado': 'entregada',
          },
        ],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(transportistaProfile);
        }
        if (request.url.path == '/api/asignaciones-multiples' &&
            request.method == 'GET') {
          return jsonResponse({'data': [], 'current_page': 1, 'last_page': 1});
        }
        if (request.url.path == '/api/rutas-multi' && request.method == 'GET') {
          return jsonResponse({
            'data': [detailCalls > 1 ? webUpdatedRuta : initialRuta],
            'current_page': 1,
            'last_page': 1,
          });
        }
        if (request.url.path == '/api/rutas-multi/18' &&
            request.method == 'GET') {
          detailCalls++;
          return jsonResponse(detailCalls == 1 ? initialRuta : webUpdatedRuta);
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver asignaciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mis envíos y entregas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ruta Valle Alto #18'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('entrega.estado_badge')),
          matching: find.text('Planificada'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('entrega.actualizar')));
      await tester.pumpAndSettle();

      expect(detailCalls, 2);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('entrega.estado_badge')),
          matching: find.text('Completada'),
        ),
        findsOneWidget,
      );
      expect(find.text('Cierre: 2026-11-22T09:15:00Z'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('entrega.avanzar.en_ruta')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('entrega.volver')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('entregas.actualizar')));
      await tester.pumpAndSettle();

      expect(find.text('Completada'), findsOneWidget);
    },
  );
}
