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
}
