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

  const jefePlantaProfile = {
    'usuarioid': 20,
    'nombre': 'Elena',
    'apellido': 'Vargas',
    'email': 'elena@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 6, 'name': 'jefe_planta'},
    ],
    'permissions': ['recepcion_planta.view', 'recepcion_planta.confirm'],
  };

  const pendingRecepcion = {
    'pedidoid': 60,
    'numero_solicitud': 'PED-PLANTA-060',
    'envioasignacionmultipleid': 14,
    'externo_envio_id': 'ENV-14',
    'estado': 'en_transporte_planta',
    'almacenid': 8,
    'fecha_recepcion_planta': null,
    'recepcion_usuarioid': null,
    'lineas': [
      {
        'detallepedidoid': 41,
        'producto': 'Papa Huaycha',
        'cantidad_enviada': '100',
        'unidad': 'kg',
        'produccionalmacenamientoid': 9,
        'produccionid': 71,
        'loteid': 25,
      },
    ],
    'recepcion': null,
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
    await storage.saveToken('1|recepcion-test');
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
    'Permite registrar las cantidades de materia prima recibidas en planta',
    (tester) async {
      var received = false;
      Map<String, dynamic>? sentBody;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(jefePlantaProfile);
        }
        if (request.url.path == '/api/planta/recepciones' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': received ? <Map<String, Object?>>[] : [pendingRecepcion],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/planta/recepciones/60' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': received
                ? {
                    ...pendingRecepcion,
                    'estado': 'recibido',
                    'fecha_recepcion_planta': '2026-11-21T12:05:00Z',
                    'recepcion': [
                      {'detallepedidoid': 41, 'cantidad_recibida': '98.5'},
                    ],
                  }
                : pendingRecepcion,
          });
        }
        if (request.url.path == '/api/planta/recepciones/60/confirmar' &&
            request.method == 'POST') {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          received = true;
          return jsonResponse({
            'data': {
              ...pendingRecepcion,
              'estado': 'recibido',
              'fecha_recepcion_planta': '2026-11-21T12:05:00Z',
              'recepcion': [
                {'detallepedidoid': 41, 'cantidad_recibida': '98.5'},
              ],
            },
          });
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver recepciones en planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PED-PLANTA-060'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('recepcion.cantidad.41')),
        '98.5',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('recepcion.confirmar')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recepcion.confirmar')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar recepción'),
      );
      await tester.pumpAndSettle();

      expect(sentBody, {
        'cantidades': {'41': '98.5'},
      });
      expect(find.text('Recibida'), findsOneWidget);
      expect(find.text('98.5 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'Cada recepción identifica el lote de origen correspondiente en listado y detalle',
    (tester) async {
      final multiLineRecepcion = {
        ...pendingRecepcion,
        'lineas': [
          ...(pendingRecepcion['lineas'] as List),
          {
            'detallepedidoid': 42,
            'producto': 'Quinua Real',
            'cantidad_enviada': '50',
            'unidad': 'kg',
            'produccionalmacenamientoid': null,
            'produccionid': null,
            'loteid': null,
          },
        ],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(jefePlantaProfile);
        }
        if (request.url.path == '/api/planta/recepciones' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [multiLineRecepcion],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/planta/recepciones/60' &&
            request.method == 'GET') {
          return jsonResponse({'data': multiLineRecepcion});
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver recepciones en planta'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Origen: Lote #25 · Cosecha #71'),
        findsOneWidget,
      );

      await tester.tap(find.text('PED-PLANTA-060'));
      await tester.pumpAndSettle();

      expect(
        find.text('Lote de origen: Lote #25 · Cosecha #71'),
        findsOneWidget,
      );
      expect(
        find.text('Lote de origen: Sin lote de origen vinculado'),
        findsOneWidget,
      );
    },
  );
}
