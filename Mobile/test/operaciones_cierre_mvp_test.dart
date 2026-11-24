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

  const mayoristaUser = {
    'usuarioid': 15,
    'nombre': 'Diego',
    'apellido': 'Rojas',
    'email': 'diego@agrofusion.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 5, 'name': 'mayorista'},
    ],
    'permissions': ['incidentes.view', 'incidentes.resolve'],
  };

  const transportistaUser = {
    'usuarioid': 20,
    'nombre': 'Mario',
    'apellido': 'Vargas',
    'email': 'mario@agrofusion.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 4, 'name': 'transportista'},
    ],
    'permissions': ['incidentes.view', 'incidentes.create'],
  };

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> openModule(
    WidgetTester tester,
    ApiClient api,
    String moduleLabel,
  ) async {
    await tester.pumpWidget(
      AgroFusionApp(apiClient: api, sessionStorage: storage),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(moduleLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(moduleLabel));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Un responsable con incidentes.resolve abre el detalle de una incidencia, exige nota y la resuelve',
    (tester) async {
      await storage.saveToken('1|mayorista-token');
      var resolved = false;
      Map<String, dynamic>? sentBody;

      Map<String, dynamic> incidenteJson() => {
        'incidenteenvioid': 42,
        'tipo': 'Empaque dañado',
        'descripcion': 'Dos cajas llegaron golpeadas en la descarga.',
        'estado': resolved ? 'resuelto' : 'abierto',
        'seguimiento': resolved ? 'Resuelta' : 'Pendiente de resolución',
        'afectado_referencia': 'Pedido de distribución #120',
        'reportado_por': {'usuarioid': 20, 'nombre': 'Mario Vargas'},
        'responsable_nombre': 'Diego Rojas',
        'created_at': '2026-11-23T14:00:00Z',
        'nota_resolucion': resolved
            ? 'Se repusieron las dos cajas dañadas sin costo.'
            : null,
        'fecha_resolucion': resolved ? '2026-11-24T10:30:00Z' : null,
        'resuelto_por': resolved
            ? {'usuarioid': 15, 'nombre': 'Diego Rojas'}
            : null,
        'puede_resolver': !resolved,
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse(mayoristaUser);
          }
          if (request.url.path == '/api/incidentes' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': [incidenteJson()],
              'current_page': 1,
              'last_page': 1,
              'total': 1,
            });
          }
          if (request.url.path == '/api/incidentes/42' &&
              request.method == 'GET') {
            return jsonResponse(incidenteJson());
          }
          if (request.url.path == '/api/incidentes/42/resolver' &&
              request.method == 'PATCH') {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            resolved = true;
            return jsonResponse(incidenteJson());
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await openModule(tester, api, 'Incidentes');

      expect(find.text('Empaque dañado'), findsOneWidget);
      await tester.tap(find.text('Empaque dañado'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de incidencia'), findsOneWidget);
      expect(
        find.text('Dos cajas llegaron golpeadas en la descarga.'),
        findsOneWidget,
      );
      expect(find.text('Pedido de distribución #120'), findsOneWidget);

      final resolveBtn = find.byKey(const ValueKey('incidente.resolver'));
      await tester.ensureVisible(resolveBtn);
      await tester.tap(resolveBtn);
      await tester.pumpAndSettle();

      // Exige nota obligatoria antes de enviar
      await tester.tap(
        find.byKey(const ValueKey('incidente.confirmar_resolucion')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Ingresa una explicación de la solución aplicada.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('incidente.nota_resolucion')),
        'Se repusieron las dos cajas dañadas sin costo.',
      );
      await tester.tap(
        find.byKey(const ValueKey('incidente.confirmar_resolucion')),
      );
      await tester.pumpAndSettle();

      expect(sentBody, {
        'nota_resolucion': 'Se repusieron las dos cajas dañadas sin costo.',
      });
      expect(
        find.byKey(const ValueKey('incidente.solucion_card')),
        findsOneWidget,
      );
      expect(
        find.text('Se repusieron las dos cajas dañadas sin costo.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('incidente.resolver')), findsNothing);
    },
  );

  testWidgets(
    'Un usuario sin permiso incidentes.resolve ve el detalle pero no puede resolver la incidencia',
    (tester) async {
      await storage.saveToken('1|transportista-token');

      const incidenteAbierto = {
        'incidenteenvioid': 43,
        'tipo': 'Demora en ruta',
        'descripcion': 'Bloqueo temporal en carretera.',
        'estado': 'abierto',
        'seguimiento': 'Pendiente de resolución',
        'puede_resolver': false,
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse(transportistaUser);
          }
          if (request.url.path == '/api/incidentes' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': const [incidenteAbierto],
              'current_page': 1,
              'last_page': 1,
              'total': 1,
            });
          }
          if (request.url.path == '/api/incidentes/43' &&
              request.method == 'GET') {
            return jsonResponse(incidenteAbierto);
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await openModule(tester, api, 'Incidentes');
      await tester.tap(find.text('Demora en ruta'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de incidencia'), findsOneWidget);
      expect(find.text('Bloqueo temporal en carretera.'), findsOneWidget);
      expect(find.byKey(const ValueKey('incidente.resolver')), findsNothing);
    },
  );

  testWidgets(
    'Certificaciones abre su detalle, muestra estado/hash blockchain y descarga el PDF',
    (tester) async {
      await storage.saveToken('1|jefe-token');
      var pdfDownloads = 0;

      const jefeUser = {
        'usuarioid': 5,
        'nombre': 'Carlos',
        'apellido': 'Vega',
        'email': 'jefe@agrofusion.test',
        'activo': true,
        'estado_cuenta': 'aprobado',
        'roles': [
          {'id': 2, 'name': 'jefe_agricultor'},
        ],
        'permissions': ['certificaciones.view'],
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') return jsonResponse(jefeUser);
          if (request.url.path == '/api/certificaciones' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': const [
                {
                  'certificacionid': 7,
                  'codigo_certificado': 'CERT-2026-007',
                  'resultado': 'Aprobado',
                },
              ],
              'current_page': 1,
              'last_page': 1,
              'total': 1,
            });
          }
          if (request.url.path == '/api/certificaciones/7' &&
              request.method == 'GET') {
            return jsonResponse({
              'certificacionid': 7,
              'loteid': 25,
              'codigo_certificado': 'CERT-2026-007',
              'resultado': 'Aprobado',
              'observaciones': 'Sin residuos detectados.',
              'fecha_certificacion': '2026-11-18T10:00:00Z',
              'archivo_disponible': true,
              'lote': {'loteid': 25, 'nombre': 'Parcela Norte'},
              'usuario': {'usuarioid': 9, 'nombre': 'Ana', 'apellido': 'Mora'},
              'blockchain_estado': 'confirmado',
              'blockchain_tx_hash': '0xdeadbeef123456',
              'blockchain_network': 'Polygon Amoy',
            });
          }
          if (request.url.path == '/api/certificaciones/7/archivo' &&
              request.method == 'GET') {
            pdfDownloads++;
            return http.Response.bytes(
              utf8.encode('%PDF-1.4 fake certificate bytes'),
              200,
              headers: {'content-type': 'application/pdf'},
            );
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await openModule(tester, api, 'Certificaciones');
      await tester.tap(find.text('CERT-2026-007'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de certificación'), findsOneWidget);
      expect(find.text('Parcela Norte'), findsOneWidget);
      expect(find.text('Confirmado en blockchain'), findsOneWidget);
      expect(find.text('0xdeadbeef123456'), findsOneWidget);

      final pdfBtn = find.byKey(const ValueKey('certificacion.abrir_archivo'));
      await tester.ensureVisible(pdfBtn);
      await tester.tap(pdfBtn);
      await tester.pumpAndSettle();

      expect(pdfDownloads, 1);
      expect(
        find.byKey(const ValueKey('certificacion.descarga_confirmada')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Documentos de entrega abre su detalle y descarga el respaldo adjunto',
    (tester) async {
      await storage.saveToken('1|doc-token');
      var docDownloads = 0;

      const docUser = {
        'usuarioid': 20,
        'nombre': 'Mario',
        'apellido': 'Vargas',
        'email': 'mario@agrofusion.test',
        'activo': true,
        'estado_cuenta': 'aprobado',
        'roles': [
          {'id': 4, 'name': 'transportista'},
        ],
        'permissions': ['documentos.view'],
      };

      const docJson = {
        'documentoentregaid': 19,
        'titulo': 'Acta de entrega #19',
        'tipo_documento': 'acta_entrega',
        'pedidoid': 120,
        'archivo_path': 'documentos_entrega/acta19.pdf',
        'usuario': {'usuarioid': 20, 'nombre': 'Mario', 'apellido': 'Vargas'},
        'metadata': {
          'original_name': 'acta19.pdf',
          'mime': 'application/pdf',
          'size': 4096,
        },
        'created_at': '2026-11-22T15:00:00Z',
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') return jsonResponse(docUser);
          if (request.url.path == '/api/documentos-entrega' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': const [docJson],
              'current_page': 1,
              'last_page': 1,
              'total': 1,
            });
          }
          if (request.url.path == '/api/documentos-entrega/19/download' &&
              request.method == 'GET') {
            docDownloads++;
            return http.Response.bytes(
              utf8.encode('%PDF-1.4 acta de entrega'),
              200,
              headers: {'content-type': 'application/pdf'},
            );
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await openModule(tester, api, 'Documentos de entrega');
      await tester.tap(find.text('Acta de entrega #19'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de documento'), findsOneWidget);
      expect(find.text('acta19.pdf'), findsOneWidget);
      expect(find.text('4.0 KB'), findsOneWidget);

      final downloadBtn = find.byKey(const ValueKey('documento.abrir_archivo'));
      await tester.ensureVisible(downloadBtn);
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      expect(docDownloads, 1);
      expect(
        find.byKey(const ValueKey('documento.descarga_confirmada')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Insumos y existencias de almacén PDV muestran código de trazabilidad y abren la vista pública',
    (tester) async {
      await storage.saveToken('1|minorista-token');

      const minoristaUser = {
        'usuarioid': 33,
        'nombre': 'Elena',
        'apellido': 'Paz',
        'email': 'elena@agrofusion.test',
        'activo': true,
        'estado_cuenta': 'aprobado',
        'roles': [
          {'id': 6, 'name': 'minorista'},
        ],
        'permissions': ['inventario.view'],
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') return jsonResponse(minoristaUser);
          if (request.url.path == '/api/insumos' && request.method == 'GET') {
            return jsonResponse({
              'data': const [
                {
                  'insumoid': 90,
                  'nombre': 'Hojuelas de Papa 500 g',
                  'stock': 20,
                  'descripcion': 'Producto terminado en tienda',
                  'codigo_trazabilidad': 'TRZ-PDV-20261124-PDV90',
                },
              ],
              'current_page': 1,
              'last_page': 1,
              'total': 1,
            });
          }
          if (request.url.path == '/api/almacenes' && request.method == 'GET') {
            return jsonResponse({
              'data': const [
                {
                  'almacenid': 8,
                  'nombre': 'Punto de Venta Central',
                  'ubicacion': 'Av. América #123',
                },
              ],
              'current_page': 1,
              'last_page': 1,
              'total': 1,
            });
          }
          if (request.url.path == '/api/almacenes/8/existencias' &&
              request.method == 'GET') {
            return jsonResponse({
              'almacen': {'almacenid': 8, 'nombre': 'Punto de Venta Central'},
              'data': const [
                {
                  'insumoid': 90,
                  'nombre': 'Hojuelas de Papa 500 g',
                  'unidad': 'bolsas',
                  'cantidad_fisica': '20',
                  'cantidad_disponible': '20',
                  'codigo_trazabilidad': 'TRZ-PDV-20261124-PDV90',
                },
              ],
            });
          }
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-PDV90' &&
              request.method == 'GET') {
            return jsonResponse({
              'data': {
                'codigo': 'TRZ-PDV-20261124-PDV90',
                'producto': 'Hojuelas de Papa 500 g',
                'lote_agricola': 'Parcela Norte',
                'punto_venta': 'Punto de Venta Central',
                'total_eventos': 1,
                'eventos': const [
                  {
                    'etapa': 'pdv',
                    'titulo': 'Disponible en tienda',
                    'fecha_fmt': '24/11/2026 09:00',
                  },
                ],
              },
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      // 1) Desde el módulo Insumos
      await openModule(tester, api, 'Insumos');
      expect(find.textContaining('TRZ-PDV-20261124-PDV90'), findsOneWidget);

      final insumoBtn = find.byKey(const ValueKey('insumo.trazabilidad.90'));
      await tester.ensureVisible(insumoBtn);
      await tester.tap(insumoBtn);
      await tester.pumpAndSettle();

      expect(find.text('Trazabilidad del producto'), findsOneWidget);
      expect(find.text('TRZ-PDV-20261124-PDV90'), findsOneWidget);

      // Volver atrás al listado de Insumos y luego a Trabajo -> Almacenes
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Almacenes'));
      await tester.tap(find.text('Almacenes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Punto de Venta Central'));
      await tester.pumpAndSettle();

      final almacenBtn = find.byKey(
        const ValueKey('almacen.existencia.trazabilidad.90'),
      );
      await tester.ensureVisible(almacenBtn);
      await tester.tap(almacenBtn);
      await tester.pumpAndSettle();

      expect(find.text('Trazabilidad del producto'), findsOneWidget);
      expect(find.text('Hojuelas de Papa 500 g'), findsOneWidget);
    },
  );

  testWidgets(
    'Bloquea acceso directo sin permisos a detalle de incidencias, certificaciones y documentos antes de consultar la API',
    (tester) async {
      await storage.saveToken('1|sin-permisos');
      var apiDataCalls = 0;

      const sinPermisosUser = {
        'usuarioid': 50,
        'nombre': 'Raúl',
        'apellido': 'Mendez',
        'email': 'raul@agrofusion.test',
        'activo': true,
        'estado_cuenta': 'aprobado',
        'roles': [
          {'id': 3, 'name': 'agricultor'},
        ],
        'permissions': ['lotes.view'],
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse(sinPermisosUser);
          }
          apiDataCalls++;
          return jsonResponse({'message': 'Forbidden'}, 403);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(apiClient: api, sessionStorage: storage),
      );
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      for (final route in const [
        '/modules/incidentes/42',
        '/modules/certificaciones/7',
        '/modules/documentos-entrega/19',
      ]) {
        navigator.pushNamed(route).ignore();
        await tester.pumpAndSettle();
        expect(find.text('Acceso no autorizado'), findsOneWidget);
        navigator.pop();
        await tester.pumpAndSettle();
      }

      expect(apiDataCalls, 0);
    },
  );

  testWidgets(
    'El administrador supervisa incidencias sin acción de resolver y un 403 del servidor al resolver se informa sin fallar',
    (tester) async {
      // 1) Admin: solo supervisión
      await storage.saveToken('1|admin-token');
      const adminUser = {
        'usuarioid': 1,
        'nombre': 'Admin',
        'apellido': 'Sistema',
        'email': 'admin@agrofusion.test',
        'activo': true,
        'estado_cuenta': 'aprobado',
        'roles': [
          {'id': 1, 'name': 'admin'},
        ],
        'permissions': ['incidentes.view', 'incidentes.resolve'],
      };
      const incidenteAbierto = {
        'incidenteenvioid': 44,
        'tipo': 'Diferencia de peso',
        'descripcion': 'Faltaron 5 kg al recibir el envío.',
        'estado': 'abierto',
        'seguimiento': 'Pendiente de resolución',
        'puede_resolver': true,
      };

      final adminApi = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') return jsonResponse(adminUser);
          if (request.url.path == '/api/incidentes/44') {
            return jsonResponse(incidenteAbierto);
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(adminApi.close);

      await tester.pumpWidget(
        AgroFusionApp(apiClient: adminApi, sessionStorage: storage),
      );
      await tester.pumpAndSettle();

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/modules/incidentes/44')
          .ignore();
      await tester.pumpAndSettle();

      expect(find.text('Diferencia de peso'), findsOneWidget);
      expect(find.byKey(const ValueKey('incidente.resolver')), findsNothing);

      // 2) Mayorista recibe 403 del backend al resolver -> muestra aviso sin romperse
      await storage.saveToken('1|mayorista-403');
      final rejectApi = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse(mayoristaUser);
          }
          if (request.url.path == '/api/incidentes/44' &&
              request.method == 'GET') {
            return jsonResponse(incidenteAbierto);
          }
          if (request.url.path == '/api/incidentes/44/resolver' &&
              request.method == 'PATCH') {
            return jsonResponse({
              'message':
                  'No estás asignado como responsable de esta incidencia.',
            }, 403);
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(rejectApi.close);

      await tester.pumpWidget(
        AgroFusionApp(
          key: const ValueKey('reject-app'),
          apiClient: rejectApi,
          sessionStorage: storage,
        ),
      );
      await tester.pumpAndSettle();

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/modules/incidentes/44')
          .ignore();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('incidente.resolver')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('incidente.nota_resolucion')),
        'Intento de cierre sin ser responsable.',
      );
      await tester.tap(
        find.byKey(const ValueKey('incidente.confirmar_resolucion')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No estás asignado como responsable de esta incidencia.'),
        findsOneWidget,
      );
    },
  );
}
