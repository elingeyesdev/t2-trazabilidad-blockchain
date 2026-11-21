import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
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

  testWidgets('La cámara permite leer el código QR y recuperar su contenido', (
    tester,
  ) async {
    await storage.saveToken('1|qr-test');
    String? sentCode;
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient((request) async {
        if (request.url.path == '/api/envios/qr/resolver' &&
            request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentCode = body['codigo'] as String?;
          return jsonResponse(validQrResponse);
        }
        return jsonResponse({}, 404);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: QrScannerScreen(
          user: minoristaUser,
          service: ModuleService(api),
          onRefreshPermissions: () {},
          cameraBuilder: (context, onCodeDetected, onCameraIssue) => Center(
            child: FilledButton(
              key: const ValueKey('test.simular_qr'),
              onPressed: () =>
                  onCodeDetected('https://agrofusion.test/recepcion/SECRET-99'),
              child: const Text('Simular lectura'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('test.simular_qr')));
    await tester.pumpAndSettle();

    expect(sentCode, 'https://agrofusion.test/recepcion/SECRET-99');
    expect(
      find.text('https://agrofusion.test/recepcion/SECRET-99'),
      findsOneWidget,
    );
    expect(find.textContaining('RUTA-045'), findsOneWidget);
  });
}
