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

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  const mvpTraceabilityPayload = {
    'data': {
      'codigo': 'TRZ-PDV-20261124-MVP001',
      'producto': 'Hojuelas de Papa 500 g',
      'stock_actual': 30,
      'unidad': 'bolsas',
      'punto_venta': 'Mercado Central',
      'minorista': 'Tienda La Esperanza',
      'lote_agricola': 'Parcela Norte',
      'lote_codigo': 'TRZ-LOTE-MVP1',
      'pedido': 'PDV-2026-100',
      'total_eventos': 5,
      'certificaciones': [
        {
          'nombre': 'Certificación Orgánica SENASAG',
          'entidad': 'SENASAG',
          'codigo': 'CERT-MVP-001',
          'estado': 'vigente',
          'blockchain_status': 'confirmado',
          'tx_hash': '0xmvp001hashblockchain',
          'red': 'Polygon Amoy',
        },
      ],
      'eventos_agrupados': [
        {
          'key': 'agricola',
          'label': 'Producción agrícola',
          'eventos': [
            {
              'paso': 1,
              'fecha_fmt': '01/11/2026 08:00',
              'titulo': 'Siembra y cosecha certificada',
              'ubicacion': 'Parcela Norte',
            },
          ],
        },
        {
          'key': 'planta',
          'label': 'Planta procesadora',
          'eventos': [
            {
              'paso': 2,
              'fecha_fmt': '10/11/2026 11:00',
              'titulo': 'Transformación y empaque en planta',
              'ubicacion': 'Planta Valle Alto',
            },
          ],
        },
        {
          'key': 'mayorista',
          'label': 'Centro mayorista',
          'eventos': [
            {
              'paso': 3,
              'fecha_fmt': '14/11/2026 15:00',
              'titulo': 'Recepción en almacén mayorista',
              'ubicacion': 'Almacén Central',
            },
          ],
        },
        {
          'key': 'distribucion',
          'label': 'Distribución al PDV',
          'eventos': [
            {
              'paso': 4,
              'fecha_fmt': '18/11/2026 09:00',
              'titulo': 'Entrega confirmada con firma',
              'ubicacion': 'Ruta Zona Sur',
            },
          ],
        },
        {
          'key': 'pdv',
          'label': 'Punto de venta',
          'eventos': [
            {
              'paso': 5,
              'fecha_fmt': '18/11/2026 13:00',
              'titulo': 'Disponible para consumidor',
              'ubicacion': 'Mercado Central',
            },
          ],
        },
      ],
    },
  };

  Map<String, dynamic> profileFor({
    required int id,
    required String name,
    required String role,
    required List<String> permissions,
  }) => {
    'usuarioid': id,
    'nombre': name,
    'apellido': 'Demo',
    'email': '$role@agrofusion.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': id, 'name': role},
    ],
    'permissions': permissions,
  };

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Rol 1 — Consumidor sin login consulta la cadena completa de trazabilidad MVP sin token',
    (tester) async {
      String? authHeader;
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-MVP001') {
            authHeader = request.headers['Authorization'];
            return jsonResponse(mvpTraceabilityPayload);
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(
          apiClient: api,
          sessionStorage: storage,
          trazabilidadCameraBuilder: (_, onDetect, _) => Center(
            child: TextButton(
              key: const ValueKey('mvp.scan'),
              onPressed: () => onDetect(
                'https://agrofusion.test/trazabilidad/TRZ-PDV-20261124-MVP001',
              ),
              child: const Text('Escanear'),
            ),
          ),
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

      await tester.tap(find.byKey(const ValueKey('mvp.scan')));
      await tester.pumpAndSettle();

      final openFull = find.byKey(const ValueKey('trazabilidad.ver_completa'));
      await tester.ensureVisible(openFull);
      await tester.tap(openFull);
      await tester.pumpAndSettle();

      expect(authHeader, isNull);
      expect(find.text('Hojuelas de Papa 500 g'), findsOneWidget);
      expect(find.text('Verificado en blockchain'), findsOneWidget);
      expect(find.text('Producción agrícola'), findsOneWidget);
      expect(find.text('Planta procesadora'), findsOneWidget);
      expect(find.text('Centro mayorista'), findsOneWidget);
      expect(find.text('Distribución al PDV'), findsOneWidget);
      expect(find.text('Punto de venta'), findsWidgets);
    },
  );

  testWidgets(
    'Roles 2 a 9 — Cada rol operativo y de supervisión accede solo a sus módulos y acciones autorizadas',
    (tester) async {
      final scenarios =
          <
            ({
              String role,
              String name,
              List<String> permissions,
              List<String> expectedWorkModules,
              List<String> forbiddenWorkModules,
            })
          >[
            (
              role: 'admin',
              name: 'Admin',
              permissions: const [
                'usuarios.admin',
                'incidentes.view',
                'lotes.view',
                'certificaciones.view',
              ],
              expectedWorkModules: const ['Usuarios', 'Incidentes', 'Lotes'],
              forbiddenWorkModules: const ['Recepciones en planta'],
            ),
            (
              role: 'jefe_agricultor',
              name: 'JefeCampo',
              permissions: const [
                'lotes.view',
                'lotes.create',
                'lotes.update',
                'certificaciones.view',
                'inventario.view',
              ],
              expectedWorkModules: const [
                'Lotes',
                'Actividades',
                'Certificaciones',
              ],
              forbiddenWorkModules: const ['Usuarios', 'Tareas de planta'],
            ),
            (
              role: 'agricultor',
              name: 'OperarioCampo',
              permissions: const ['lotes.view'],
              expectedWorkModules: const ['Lotes', 'Actividades'],
              forbiddenWorkModules: const ['Usuarios', 'Pedidos', 'Almacenes'],
            ),
            (
              role: 'jefe_planta',
              name: 'JefePlanta',
              permissions: const [
                'lote_produccion.view',
                'recepcion_planta.view',
                'inventario.view',
                'incidentes.view',
                'incidentes.resolve',
              ],
              expectedWorkModules: const ['Recepciones en planta', 'Almacenes'],
              forbiddenWorkModules: const ['Tareas de planta', 'Usuarios'],
            ),
            (
              role: 'planta',
              name: 'OperarioPlanta',
              permissions: const ['lote_produccion.view'],
              expectedWorkModules: const ['Tareas de planta'],
              forbiddenWorkModules: const ['Recepciones en planta', 'Usuarios'],
            ),
            (
              role: 'transportista',
              name: 'Chofer',
              permissions: const [
                'asignaciones.view',
                'rutas_multi.view',
                'documentos.view',
                'incidentes.view',
                'incidentes.create',
              ],
              expectedWorkModules: const [
                'Asignaciones',
                'Documentos de entrega',
                'Incidentes',
              ],
              forbiddenWorkModules: const ['Usuarios', 'Lotes'],
            ),
            (
              role: 'mayorista',
              name: 'Mayorista',
              permissions: const [
                'pedidos_distribucion.view',
                'pedidos_distribucion.update',
                'inventario.view',
                'incidentes.view',
                'incidentes.resolve',
              ],
              expectedWorkModules: const ['Pedidos', 'Almacenes', 'Incidentes'],
              forbiddenWorkModules: const ['Usuarios', 'Tareas de planta'],
            ),
            (
              role: 'minorista',
              name: 'Minorista',
              permissions: const [
                'pedidos_distribucion.view',
                'pedidos_distribucion.create',
                'inventario.view',
              ],
              expectedWorkModules: const ['Pedidos', 'Almacenes', 'Insumos'],
              forbiddenWorkModules: const ['Usuarios', 'Asignaciones'],
            ),
          ];

      for (var i = 0; i < scenarios.length; i++) {
        final scenario = scenarios[i];
        await storage.saveToken('1|token-${scenario.role}');
        final profile = profileFor(
          id: i + 10,
          name: scenario.name,
          role: scenario.role,
          permissions: scenario.permissions,
        );

        final api = ApiClient(
          config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
          sessionStorage: storage,
          client: MockClient((request) async {
            if (request.url.path == '/api/me') return jsonResponse(profile);
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
          AgroFusionApp(
            key: ValueKey('role-app-${scenario.role}'),
            apiClient: api,
            sessionStorage: storage,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hola, ${scenario.name}'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home.trazabilidad_publica')),
          findsOneWidget,
        );

        await tester.tap(find.text('Trabajo'));
        await tester.pumpAndSettle();

        for (final expected in scenario.expectedWorkModules) {
          expect(
            find.text(expected),
            findsWidgets,
            reason: 'Rol ${scenario.role} debe ver $expected',
          );
        }
        for (final forbidden in scenario.forbiddenWorkModules) {
          expect(
            find.text(forbidden),
            findsNothing,
            reason: 'Rol ${scenario.role} no debe ver $forbidden',
          );
        }
      }
    },
  );
}
