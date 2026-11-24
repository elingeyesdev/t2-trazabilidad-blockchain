import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/trazabilidad_publica_models.dart';
import 'package:agrofusion_mobile/screens/modules/qr_scanner_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();

  const approvedUser = {
    'usuarioid': 12,
    'nombre': 'Lucía',
    'apellido': 'Quispe',
    'email': 'lucia@agrofusion.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 3, 'name': 'minorista'},
    ],
    'permissions': ['pedidos_distribucion.view'],
  };

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Widget fakeCamera(
    BuildContext context,
    ValueChanged<String> onCodeDetected,
    ValueChanged<QrCameraIssue> onCameraIssue,
  ) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: const ValueKey('fake.camera.detect_pdv'),
          onPressed: () => onCodeDetected('TRZ-PDV-20261124-ABC123'),
          child: const Text('Simular QR PDV'),
        ),
        TextButton(
          key: const ValueKey('fake.camera.detect_url'),
          onPressed: () => onCodeDetected(
            'https://agrofusion.up.railway.app/trazabilidad/trz-pdv-20261124-xyz789/?origen=etiqueta',
          ),
          child: const Text('Simular QR URL'),
        ),
        TextButton(
          key: const ValueKey('fake.camera.detect_invalid'),
          onPressed: () => onCodeDetected('https://agrofusion.test/login'),
          child: const Text('Simular QR inválido'),
        ),
        TextButton(
          key: const ValueKey('fake.camera.deny'),
          onPressed: () => onCameraIssue(QrCameraIssue.permissionDenied),
          child: const Text('Simular permiso denegado'),
        ),
      ],
    ),
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Un consumidor sin sesión puede abrir la consulta de trazabilidad desde LoginScreen',
    (tester) async {
      var authCalls = 0;
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          authCalls++;
          return jsonResponse({'message': 'Unexpected call'}, 500);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(
          apiClient: api,
          sessionStorage: storage,
          trazabilidadCameraBuilder: fakeCamera,
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('login.trazabilidad_publica'));
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Consultar trazabilidad'), findsOneWidget);
      expect(find.text('Escanear QR'), findsOneWidget);
      expect(find.text('Ingresar código'), findsOneWidget);
      expect(authCalls, 0);
    },
  );

  testWidgets(
    'Un usuario autenticado también cuenta con acceso rápido a trazabilidad desde Inicio',
    (tester) async {
      await storage.saveToken('1|minorista-token');
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse(approvedUser);
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(
          apiClient: api,
          sessionStorage: storage,
          trazabilidadCameraBuilder: fakeCamera,
        ),
      );
      await tester.pumpAndSettle();

      final shortcut = find.byKey(const ValueKey('home.trazabilidad_publica'));
      expect(shortcut, findsOneWidget);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();

      expect(find.text('Consultar trazabilidad'), findsOneWidget);
    },
  );

  testWidgets(
    'TrazabilidadLookupScreen permite escanear por cámara, manejar permiso denegado e ingresar código manual',
    (tester) async {
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-ABC123') {
            return jsonResponse({
              'codigo': 'TRZ-PDV-20261124-ABC123',
              'producto': 'Hojuelas de Papa 500 g',
              'lote_agricola': 'Parcela Norte',
              'punto_venta': 'Mercado Central',
              'total_eventos': 6,
            });
          }
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-XYZ789') {
            return jsonResponse({
              'codigo': 'TRZ-PDV-20261124-XYZ789',
              'producto': 'Papa Prefrita 1 kg',
              'lote_agricola': 'Lote Sur',
              'punto_venta': 'Tienda Norte',
              'total_eventos': 5,
            });
          }
          if (request.url.path == '/api/trazabilidad/TRZ-2026-LOTE01') {
            return jsonResponse({
              'codigo': 'TRZ-2026-LOTE01',
              'producto': 'Papa Huaycha',
              'lote_agricola': 'Parcela Norte',
              'total_eventos': 4,
            });
          }
          return jsonResponse({'message': 'No encontrado'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(
          apiClient: api,
          sessionStorage: storage,
          trazabilidadCameraBuilder: fakeCamera,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('login.trazabilidad_publica')),
      );
      await tester.tap(
        find.byKey(const ValueKey('login.trazabilidad_publica')),
      );
      await tester.pumpAndSettle();

      // 1) Escaneo de cámara
      await tester.tap(find.byKey(const ValueKey('fake.camera.detect_pdv')));
      await tester.pumpAndSettle();
      expect(find.text('TRZ-PDV-20261124-ABC123'), findsOneWidget);

      // 2) Permiso de cámara denegado -> pasar a ingreso manual
      await tester.tap(find.byKey(const ValueKey('fake.camera.deny')));
      await tester.pumpAndSettle();
      expect(find.text('Permiso de cámara denegado'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('trazabilidad.cambiar_a_manual')),
      );
      await tester.pumpAndSettle();

      // 3) Validación de campo vacío en modo manual
      await tester.tap(
        find.byKey(const ValueKey('trazabilidad.consultar_btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Ingresa un código de trazabilidad o pega el enlace del QR.'),
        findsOneWidget,
      );

      // 4) Ingreso manual de código válido
      await tester.enterText(
        find.byKey(const ValueKey('trazabilidad.codigo_input')),
        'TRZ-2026-LOTE01',
      );
      await tester.tap(
        find.byKey(const ValueKey('trazabilidad.consultar_btn')),
      );
      await tester.pumpAndSettle();
      expect(find.text('TRZ-2026-LOTE01'), findsWidgets);
    },
  );

  test(
    'TrazabilidadCodigoParser extrae y normaliza códigos desde URLs completas o códigos directos',
    () {
      expect(
        TrazabilidadCodigoParser.extract(
          'https://agrofusion.up.railway.app/trazabilidad/TRZ-PDV-20261124-ABC123',
        ),
        'TRZ-PDV-20261124-ABC123',
      );
      expect(
        TrazabilidadCodigoParser.extract(
          'http://localhost:8000/api/trazabilidad/trz-2026-lote09/?src=qr',
        ),
        'TRZ-2026-LOTE09',
      );
      expect(
        TrazabilidadCodigoParser.extract(
          'https://agrofusion.test/trazabilidad?codigo=trz-pdv-20261124-q99999',
        ),
        'TRZ-PDV-20261124-Q99999',
      );
      expect(
        TrazabilidadCodigoParser.extract(
          '/trazabilidad/TRZ-PDV-20261124-REL123',
        ),
        'TRZ-PDV-20261124-REL123',
      );
      expect(
        TrazabilidadCodigoParser.extract('  trz-pdv-20261124-abc123  '),
        'TRZ-PDV-20261124-ABC123',
      );

      expect(TrazabilidadCodigoParser.extract(''), isNull);
      expect(TrazabilidadCodigoParser.extract('   '), isNull);
      expect(TrazabilidadCodigoParser.extract('texto con espacios'), isNull);
      expect(
        TrazabilidadCodigoParser.extract('https://agrofusion.test/login'),
        isNull,
      );
      expect(
        TrazabilidadCodigoParser.extract(
          'https://agrofusion.test/recepcion/token123',
        ),
        isNull,
      );
    },
  );

  testWidgets(
    'Al escanear una URL completa extrae el código normalizado y rechaza enlaces ajenos a trazabilidad',
    (tester) async {
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-ABC123') {
            return jsonResponse({
              'codigo': 'TRZ-PDV-20261124-ABC123',
              'producto': 'Hojuelas de Papa 500 g',
              'lote_agricola': 'Parcela Norte',
              'punto_venta': 'Mercado Central',
              'total_eventos': 6,
            });
          }
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-XYZ789') {
            return jsonResponse({
              'codigo': 'TRZ-PDV-20261124-XYZ789',
              'producto': 'Papa Prefrita 1 kg',
              'lote_agricola': 'Lote Sur',
              'punto_venta': 'Tienda Norte',
              'total_eventos': 5,
            });
          }
          if (request.url.path == '/api/trazabilidad/TRZ-2026-LOTE01') {
            return jsonResponse({
              'codigo': 'TRZ-2026-LOTE01',
              'producto': 'Papa Huaycha',
              'lote_agricola': 'Parcela Norte',
              'total_eventos': 4,
            });
          }
          return jsonResponse({'message': 'No encontrado'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(
          apiClient: api,
          sessionStorage: storage,
          trazabilidadCameraBuilder: fakeCamera,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('login.trazabilidad_publica')),
      );
      await tester.tap(
        find.byKey(const ValueKey('login.trazabilidad_publica')),
      );
      await tester.pumpAndSettle();

      // URL inválida (ajena a trazabilidad)
      await tester.tap(
        find.byKey(const ValueKey('fake.camera.detect_invalid')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('trazabilidad.error_parseo')),
        findsOneWidget,
      );

      // URL pública de trazabilidad -> extrae código normalizado en mayúsculas
      await tester.tap(find.byKey(const ValueKey('fake.camera.detect_url')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('trazabilidad.error_parseo')),
        findsNothing,
      );
      expect(find.text('TRZ-PDV-20261124-XYZ789'), findsOneWidget);
    },
  );
}
