import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/screens/public/trazabilidad_publica_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/services/trazabilidad_publica_service.dart';
import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Desde la consulta pública se abre TrazabilidadPublicaScreen mostrando cabecera, origen y respaldo blockchain real',
    (tester) async {
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-ABC123') {
            return jsonResponse({
              'data': {
                'codigo': 'TRZ-PDV-20261124-ABC123',
                'producto': 'Hojuelas de Papa 500 g',
                'stock_actual': 18,
                'unidad': 'bolsas',
                'punto_venta': 'Mercado Central',
                'minorista': 'Tienda La Esperanza',
                'lote_agricola': 'Parcela Norte',
                'lote_codigo': 'TRZ-LOTE-01',
                'pedido': 'PDV-2026-045',
                'total_eventos': 5,
                'certificaciones': [
                  {
                    'nombre': 'Certificación Orgánica SENASAG',
                    'entidad': 'SENASAG',
                    'codigo': 'CERT-2026-99',
                    'estado': 'vigente',
                    'fecha': '2026-11-12',
                    'blockchain_status': 'confirmado',
                    'tx_hash': '0xabc123def456',
                    'red': 'Polygon Amoy',
                  },
                ],
                'eventos_agrupados': const [],
              },
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(
          apiClient: api,
          sessionStorage: storage,
          trazabilidadCameraBuilder: (context, onCodeDetected, _) => Center(
            child: TextButton(
              key: const ValueKey('fake.camera.scan'),
              onPressed: () => onCodeDetected('TRZ-PDV-20261124-ABC123'),
              child: const Text('Escanear'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final loginBtn = find.byKey(const ValueKey('login.trazabilidad_publica'));
      await tester.ensureVisible(loginBtn);
      await tester.tap(loginBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('fake.camera.scan')));
      await tester.pumpAndSettle();

      final openFull = find.byKey(const ValueKey('trazabilidad.ver_completa'));
      await tester.ensureVisible(openFull);
      await tester.tap(openFull);
      await tester.pumpAndSettle();

      expect(find.text('Trazabilidad del producto'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('trazabilidad.publica.header')),
        findsOneWidget,
      );
      expect(find.text('Hojuelas de Papa 500 g'), findsOneWidget);
      expect(find.text('TRZ-PDV-20261124-ABC123'), findsOneWidget);
      expect(find.text('Verificado en blockchain'), findsOneWidget);
      expect(find.text('0xabc123def456'), findsOneWidget);
      expect(find.text('Parcela Norte (TRZ-LOTE-01)'), findsOneWidget);
      expect(find.text('Mercado Central'), findsOneWidget);
      expect(find.text('Certificación Orgánica SENASAG'), findsOneWidget);
    },
  );

  testWidgets(
    'Un producto sin certificaciones muestra estado real sin sello blockchain falso',
    (tester) async {
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-NOCERT') {
            return jsonResponse({
              'codigo': 'TRZ-PDV-20261124-NOCERT',
              'producto': 'Papa Fresca 2 kg',
              'lote_agricola': 'Parcela Sur',
              'punto_venta': 'Tienda Barrio',
              'total_eventos': 2,
              'certificaciones': const [],
              'eventos': const [],
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TrazabilidadPublicaScreen(
            codigo: 'TRZ-PDV-20261124-NOCERT',
            service: TrazabilidadPublicaService(api),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Papa Fresca 2 kg'), findsOneWidget);
      expect(
        find.text('Sin certificación blockchain registrada'),
        findsOneWidget,
      );
      expect(find.text('Verificado en blockchain'), findsNothing);
    },
  );
}
