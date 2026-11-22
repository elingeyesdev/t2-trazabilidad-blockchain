import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/models/qr_envio_models.dart';
import 'package:agrofusion_mobile/screens/modules/envio_qr_detail_screen.dart';
import 'package:agrofusion_mobile/screens/modules/qr_scanner_screen.dart';
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
    permissions: {'pedidos_distribucion.view', 'pedidos_distribucion.update'},
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

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'El destinatario autorizado puede abrir la recepción del envío mediante su código',
    (tester) async {
      await storage.saveToken('1|recepcion-firma-test');
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/envios/qr/resolver' &&
              request.method == 'POST') {
            return jsonResponse(validQrResponse);
          }
          return jsonResponse({}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (settings) {
            if (settings.name == '/modules/envios/distribucion/45') {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => EnvioQrDetailScreen(
                  tipo: EnvioTipo.distribucion,
                  envioId: 45,
                  user: minoristaUser,
                  service: ModuleService(api),
                  onRefreshPermissions: () {},
                  initialResolution: settings.arguments as QrResolucionResult?,
                ),
              );
            }
            return null;
          },
          home: QrScannerScreen(
            user: minoristaUser,
            service: ModuleService(api),
            onRefreshPermissions: () {},
            cameraBuilder: (context, onCodeDetected, onCameraIssue) =>
                const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('qr.modo_manual')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('qr.manual_input')),
        'SECRET-DEST-45',
      );
      await tester.tap(find.byKey(const ValueKey('qr.manual_submit')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('qr.abrir_destino')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qr.abrir_destino')));
      await tester.pumpAndSettle();

      expect(find.text('Recepción de envío'), findsOneWidget);
      expect(find.text('RUTA-045'), findsOneWidget);
      expect(
        find.textContaining('Código QR validado para recepción.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Permite revisar e introducir las cantidades recibidas validando límites del trayecto',
    (tester) async {
      await storage.saveToken('1|recepcion-qty');
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async => jsonResponse({}, 404)),
      );
      addTearDown(api.close);

      const jefePlanta = AuthUser(
        id: 20,
        name: 'Elena',
        lastName: 'Vargas',
        email: 'elena@example.test',
        roles: ['jefe_planta'],
        permissions: {'recepcion_planta.view', 'recepcion_planta.confirm'},
      );

      final resolution = QrResolucionResult.fromJson({
        'data': {
          'recepcion_id': 20,
          'utilizado': false,
          'puede_confirmar': true,
          'envio': {
            'id': 70,
            'tipo': 'agricola',
            'referencia': 'ENV-AGR-070',
            'estado': 'en_transporte_planta',
            'destinos': [
              {'nombre': 'Planta Sur'},
            ],
            'lineas': [
              {
                'id': 501,
                'pedido_id': 60,
                'pedido': 'PED-060',
                'producto': 'Papa Huaycha',
                'cantidad_enviada': '100.000000',
                'unidad': 'kg',
              },
            ],
            'fechas': {},
            'recepciones': [],
          },
        },
      }, codigo: 'QR-AGR-70');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EnvioQrDetailScreen(
            tipo: EnvioTipo.agricola,
            envioId: 70,
            user: jefePlanta,
            service: ModuleService(api),
            onRefreshPermissions: () {},
            initialResolution: resolution,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('recepcion_envio.cantidad.501'));
      expect(field, findsOneWidget);
      expect(find.text('100'), findsOneWidget);

      await tester.enterText(field, '120');
      await tester.pumpAndSettle();
      expect(
        find.text('No puede superar la cantidad enviada (100 kg).'),
        findsOneWidget,
      );

      await tester.enterText(field, '95.5');
      await tester.pumpAndSettle();
      expect(
        find.text('No puede superar la cantidad enviada (100 kg).'),
        findsNothing,
      );
      expect(find.text('95.5'), findsOneWidget);
    },
  );
}
