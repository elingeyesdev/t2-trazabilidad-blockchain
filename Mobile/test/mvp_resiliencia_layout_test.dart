import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/screens/modules/certificacion_detail_screen.dart';
import 'package:agrofusion_mobile/screens/modules/documento_detail_screen.dart';
import 'package:agrofusion_mobile/screens/modules/incidente_detail_screen.dart';
import 'package:agrofusion_mobile/screens/public/trazabilidad_lookup_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
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

  const supervisorProfile = {
    'usuarioid': 15,
    'nombre': 'Diego',
    'apellido': 'Rojas',
    'email': 'diego@agrofusion.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 5, 'name': 'mayorista'},
    ],
    'permissions': [
      'incidentes.view',
      'incidentes.resolve',
      'certificaciones.view',
      'documentos.view',
    ],
  };

  const supervisorUser = AuthUser(
    id: 15,
    name: 'Diego',
    lastName: 'Rojas',
    email: 'diego@agrofusion.test',
    roles: ['mayorista'],
    permissions: {
      'incidentes.view',
      'incidentes.resolve',
      'certificaciones.view',
      'documentos.view',
    },
  );

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Un 401 al actualizar un detalle operativo expira la sesión y limpia los datos privados',
    (tester) async {
      await storage.saveToken('1|token-expirado');
      var expired = false;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return expired
                ? jsonResponse({'message': 'Unauthenticated.'}, 401)
                : jsonResponse(supervisorProfile);
          }
          if (request.url.path == '/api/incidentes/42') {
            if (expired) {
              return jsonResponse({'message': 'Unauthenticated.'}, 401);
            }
            return jsonResponse({
              'incidenteenvioid': 42,
              'tipo': 'Empaque dañado',
              'descripcion': 'Caja golpeada durante traslado.',
              'estado': 'abierto',
              'seguimiento': 'Pendiente de resolución',
              'puede_resolver': true,
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(apiClient: api, sessionStorage: storage),
      );
      await tester.pumpAndSettle();

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/modules/incidentes/42')
          .ignore();
      await tester.pumpAndSettle();
      expect(find.text('Empaque dañado'), findsOneWidget);

      expired = true;
      await tester.tap(find.byKey(const ValueKey('incidente.actualizar')));
      await tester.pumpAndSettle();

      expect(await storage.readToken(), isNull);
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Empaque dañado'), findsNothing);
    },
  );

  testWidgets(
    'Un fallo temporal de red al restaurar sesión permite reconectar sin perder el acceso',
    (tester) async {
      await storage.saveToken('1|token-reconexion');
      var attempts = 0;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            attempts++;
            if (attempts == 1) {
              throw http.ClientException('Sin señal');
            }
            return jsonResponse(supervisorProfile);
          }
          return jsonResponse({
            'data': const [],
            'current_page': 1,
            'last_page': 1,
            'total': 0,
          });
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(apiClient: api, sessionStorage: storage),
      );
      await tester.pumpAndSettle();

      expect(attempts, 1);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Hola, Diego'), findsOneWidget);
    },
  );

  testWidgets(
    'Las pantallas nuevas del MVP se renderizan sin RenderFlex overflow en pantalla pequeña y texto grande',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/incidentes/42') {
            return jsonResponse({
              'incidenteenvioid': 42,
              'tipo': 'Diferencia importante en recepción de mercadería',
              'descripcion':
                  'Se detectaron cajas dañadas durante la descarga en el almacén central.',
              'estado': 'abierto',
              'seguimiento': 'Pendiente de resolución',
              'afectado_referencia': 'Pedido de distribución #120',
              'reportado_por': {'usuarioid': 20, 'nombre': 'Mario Vargas'},
              'responsable_nombre': 'Diego Rojas',
              'puede_resolver': true,
            });
          }
          if (request.url.path == '/api/certificaciones/7') {
            return jsonResponse({
              'certificacionid': 7,
              'loteid': 25,
              'codigo_certificado': 'CERT-ORGANICA-2026-0007',
              'resultado': 'Aprobado',
              'observaciones':
                  'Lote cumple con todos los estándares fitosanitarios.',
              'fecha_certificacion': '2026-11-18T10:00:00Z',
              'archivo_disponible': true,
              'lote': {
                'loteid': 25,
                'nombre': 'Parcela Comunitaria Valle Alto Norte',
              },
              'usuario': {'usuarioid': 9, 'nombre': 'Ana', 'apellido': 'Mora'},
              'blockchain_estado': 'confirmado',
              'blockchain_tx_hash':
                  '0x9b8e7d6c5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e0d9c8b7a6f5e4d3c2b1a0f9e8d',
              'blockchain_network': 'Polygon Amoy',
            });
          }
          if (request.url.path == '/api/documentos-entrega') {
            return jsonResponse({
              'data': const [
                {
                  'documentoentregaid': 19,
                  'titulo':
                      'Acta de Conformidad de Entrega en Punto de Venta Central',
                  'tipo_documento': 'acta_entrega',
                  'pedidoid': 120,
                  'archivo_path': 'documentos_entrega/acta19.pdf',
                  'usuario': {
                    'usuarioid': 20,
                    'nombre': 'Mario',
                    'apellido': 'Vargas',
                  },
                  'metadata': {
                    'original_name': 'acta_entrega_pdv_19.pdf',
                    'mime': 'application/pdf',
                    'size': 8192,
                  },
                  'created_at': '2026-11-22T15:00:00Z',
                },
              ],
              'current_page': 1,
              'last_page': 1,
              'total': 1,
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      final moduleService = ModuleService(api);
      final publicService = TrazabilidadPublicaService(api);

      Future<void> pumpScaled(Widget child) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: MaterialApp(theme: AppTheme.light, home: child),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      // 1) TrazabilidadLookupScreen (cámara y manual)
      await pumpScaled(
        TrazabilidadLookupScreen(
          service: publicService,
          cameraBuilder: (_, _, _) => const Center(child: Text('Cámara')),
        ),
      );
      await tester.ensureVisible(find.text('Ingresar código'));
      await tester.tap(find.text('Ingresar código'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 2) IncidenteDetailScreen
      await pumpScaled(
        IncidenteDetailScreen(
          incidenteId: 42,
          user: supervisorUser,
          service: moduleService,
          onRefreshPermissions: () {},
        ),
      );
      expect(find.text('Resolver incidencia'), findsOneWidget);

      // 3) CertificacionDetailScreen
      await pumpScaled(
        CertificacionDetailScreen(
          certificacionId: 7,
          user: supervisorUser,
          service: moduleService,
          onRefreshPermissions: () {},
        ),
      );
      expect(find.text('Respaldo blockchain'), findsOneWidget);

      // 4) DocumentoDetailScreen
      await pumpScaled(
        DocumentoDetailScreen(
          documentoId: 19,
          user: supervisorUser,
          service: moduleService,
          onRefreshPermissions: () {},
        ),
      );
      expect(find.text('Descargar respaldo'), findsOneWidget);
    },
  );
}
