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

  testWidgets(
    'Muestra la línea de tiempo agrupada por etapas expandibles y permite filtrar eventos localmente',
    (tester) async {
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-FULL01') {
            return jsonResponse({
              'data': {
                'codigo': 'TRZ-PDV-20261124-FULL01',
                'producto': 'Hojuelas de Papa 500 g',
                'lote_agricola': 'Parcela Norte',
                'punto_venta': 'Mercado Central',
                'total_eventos': 5,
                'eventos_agrupados': [
                  {
                    'key': 'agricola',
                    'label': 'Producción agrícola',
                    'eventos': [
                      {
                        'paso': 1,
                        'fecha_fmt': '01/11/2026 08:00',
                        'titulo': 'Siembra certificada',
                        'ubicacion': 'Parcela Norte',
                        'descripcion_lineas': ['Variedad Huaycha orgánica'],
                      },
                    ],
                  },
                  {
                    'key': 'planta',
                    'label': 'Planta procesadora',
                    'eventos': [
                      {
                        'paso': 2,
                        'fecha_fmt': '10/11/2026 10:00',
                        'titulo': 'Lavado y deshidratado',
                        'ubicacion': 'Planta Valle Alto',
                        'descripcion_lineas': ['Control de humedad aprobado'],
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
                        'titulo': 'Ingreso a almacén mayorista',
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
                        'fecha_fmt': '18/11/2026 09:30',
                        'titulo': 'Despacho en camión refrigerado',
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
                        'fecha_fmt': '18/11/2026 14:15',
                        'titulo': 'Disponible en tienda',
                        'ubicacion': 'Mercado Central',
                      },
                    ],
                  },
                ],
              },
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
            codigo: 'TRZ-PDV-20261124-FULL01',
            service: TrazabilidadPublicaService(api),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Todas las etapas presentes
      expect(find.text('Producción agrícola'), findsOneWidget);
      expect(find.text('Planta procesadora'), findsOneWidget);
      expect(find.text('Centro mayorista'), findsOneWidget);
      expect(find.text('Distribución al PDV'), findsOneWidget);
      expect(find.text('Punto de venta'), findsWidgets);
      expect(find.text('Siembra certificada'), findsOneWidget);

      // Contraer y volver a expandir la etapa agrícola
      final etapaAgricola = find.byKey(
        const ValueKey('trazabilidad.etapa.agricola'),
      );
      await tester.ensureVisible(etapaAgricola);
      await tester.tap(etapaAgricola);
      await tester.pumpAndSettle();
      expect(find.text('Siembra certificada'), findsNothing);

      await tester.tap(etapaAgricola);
      await tester.pumpAndSettle();
      expect(find.text('Siembra certificada'), findsOneWidget);

      // Filtrar por término específico
      final searchField = find.byKey(
        const ValueKey('trazabilidad.publica.buscar'),
      );
      await tester.ensureVisible(searchField);
      await tester.enterText(searchField, 'deshidratado');
      await tester.pumpAndSettle();
      expect(find.text('Lavado y deshidratado'), findsOneWidget);
      expect(find.text('Siembra certificada'), findsNothing);

      // Término sin coincidencias
      await tester.enterText(searchField, 'inexistente999');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('trazabilidad.publica.sin_coincidencias')),
        findsOneWidget,
      );

      // Limpiar búsqueda restaura todas las etapas
      await tester.tap(
        find.byKey(const ValueKey('trazabilidad.publica.buscar_limpiar')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Siembra certificada'), findsOneWidget);
    },
  );

  testWidgets(
    'Permite visualizar evidencias fotográficas, abrir ruta en mapa externo, ir a versión web y consultar otro producto',
    (tester) async {
      final launchedUris = <Uri>[];
      Uri? renderedPhotoUri;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-MEDIA1') {
            return jsonResponse({
              'data': {
                'codigo': 'TRZ-PDV-20261124-MEDIA1',
                'producto': 'Hojuelas de Papa 500 g',
                'lote_agricola': 'Parcela Norte',
                'punto_venta': 'Mercado Central',
                'total_eventos': 2,
                'eventos_agrupados': [
                  {
                    'key': 'agricola',
                    'label': 'Producción agrícola',
                    'eventos': [
                      {
                        'paso': 1,
                        'fecha_fmt': '05/11/2026 09:00',
                        'titulo': 'Cosecha documentada',
                        'evidencia_foto_url': '/storage/evidencias/cosecha.jpg',
                      },
                    ],
                  },
                  {
                    'key': 'distribucion',
                    'label': 'Distribución al PDV',
                    'eventos': [
                      {
                        'paso': 2,
                        'fecha_fmt': '19/11/2026 11:30',
                        'titulo': 'Traslado al punto de venta',
                        'mapa_ruta': [
                          {
                            'lat': -17.3935,
                            'lng': -66.1570,
                            'orden': 1,
                            'label': 'Planta',
                          },
                          {
                            'lat': -17.3895,
                            'lng': -66.1568,
                            'orden': 2,
                            'label': 'Mercado Central',
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TrazabilidadPublicaScreen(
                        codigo: 'TRZ-PDV-20261124-MEDIA1',
                        service: TrazabilidadPublicaService(api),
                        externalLauncher: (uri) async {
                          launchedUris.add(uri);
                          return true;
                        },
                        evidenceImageBuilder: (_, uri) {
                          renderedPhotoUri = uri;
                          return const SizedBox(
                            key: ValueKey('fake.evidencia.img'),
                            height: 120,
                            child: Center(child: Text('Foto cargada')),
                          );
                        },
                      ),
                    ),
                  ),
                  child: const Text('Abrir trazabilidad'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir trazabilidad'));
      await tester.pumpAndSettle();

      // 1) Evidencia fotográfica
      final evidenceBtn = find.byKey(
        const ValueKey('trazabilidad.evento.evidencia.1'),
      );
      await tester.ensureVisible(evidenceBtn);
      await tester.tap(evidenceBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('trazabilidad.evidencia.dialog')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fake.evidencia.img')), findsOneWidget);
      expect(
        renderedPhotoUri.toString(),
        'https://agrofusion.test/storage/evidencias/cosecha.jpg',
      );
      await tester.tap(find.byTooltip('Cerrar evidencia'));
      await tester.pumpAndSettle();

      // 2) Mapa externo con ruta
      final mapBtn = find.byKey(const ValueKey('trazabilidad.evento.mapa.2'));
      await tester.ensureVisible(mapBtn);
      await tester.tap(mapBtn);
      await tester.pumpAndSettle();

      expect(launchedUris, hasLength(1));
      expect(launchedUris.first.host, 'www.google.com');
      expect(launchedUris.first.path, '/maps/dir/');
      expect(launchedUris.first.queryParameters['origin'], '-17.3935,-66.157');
      expect(
        launchedUris.first.queryParameters['destination'],
        '-17.3895,-66.1568',
      );

      // 3) Abrir versión web pública
      await tester.tap(
        find.byKey(const ValueKey('trazabilidad.publica.abrir_web')),
      );
      await tester.pumpAndSettle();
      expect(launchedUris, hasLength(2));
      expect(
        launchedUris.last.toString(),
        'https://agrofusion.test/trazabilidad/TRZ-PDV-20261124-MEDIA1',
      );

      // 4) Volver para consultar otro producto
      await tester.tap(
        find.byKey(const ValueKey('trazabilidad.publica.otro_producto')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Abrir trazabilidad'), findsOneWidget);
    },
  );

  testWidgets(
    'TrazabilidadPublicaScreen se renderiza sin desbordes en pantalla pequeña y texto grande',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-20261124-SMALL1') {
            return jsonResponse({
              'data': {
                'codigo': 'TRZ-PDV-20261124-SMALL1',
                'producto':
                    'Hojuelas Crujientes de Papa Orgánica Premium Selección Especial 500 g',
                'stock_actual': 42.5,
                'unidad': 'bolsas',
                'punto_venta': 'Supermercado Cooperativa Central del Valle',
                'minorista': 'Comercializadora Agrícola del Sur',
                'lote_agricola': 'Parcela Comunitaria Alto Valle Sector Norte',
                'lote_codigo': 'TRZ-LOTE-2026-0099',
                'pedido': 'PDV-2026-00998',
                'total_eventos': 2,
                'certificaciones': [
                  {
                    'nombre':
                        'Certificación de Buenas Prácticas Agrícolas y Trazabilidad',
                    'entidad': 'SENASAG Cochabamba',
                    'codigo': 'BPA-2026-008812',
                    'estado': 'vigente',
                    'blockchain_status': 'confirmado',
                    'tx_hash':
                        '0x9b8e7d6c5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e0d9c8b7a6f5e4d3c2b1a0f9e8d',
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
                        'fecha_fmt': '01/11/2026 07:45',
                        'titulo': 'Siembra y georreferenciación del lote',
                        'ubicacion': 'Parcela Comunitaria Alto Valle',
                        'referencia': 'TRZ-LOTE-2026-0099',
                        'descripcion_lineas': [
                          'Registro completo con semilla certificada y control de humedad.',
                        ],
                      },
                    ],
                  },
                  {
                    'key': 'pdv',
                    'label': 'Punto de venta',
                    'eventos': [
                      {
                        'paso': 2,
                        'fecha_fmt': '20/11/2026 16:30',
                        'titulo': 'Recepción confirmada en tienda',
                        'ubicacion':
                            'Supermercado Cooperativa Central del Valle',
                      },
                    ],
                  },
                ],
              },
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            theme: AppTheme.light,
            home: TrazabilidadPublicaScreen(
              codigo: 'TRZ-PDV-20261124-SMALL1',
              service: TrazabilidadPublicaService(api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Verificado en blockchain'), findsOneWidget);
      expect(find.text('Producción agrícola'), findsOneWidget);
      expect(find.text('Otro producto'), findsOneWidget);
      expect(find.text('Versión web'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TrazabilidadPublicaScreen maneja 404 y error de red con reintento en carga directa',
    (tester) async {
      var attempts = 0;
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-404') {
            return jsonResponse({'message': 'No encontrado'}, 404);
          }
          if (request.url.path == '/api/trazabilidad/TRZ-PDV-RETRY') {
            attempts++;
            if (attempts == 1) {
              throw http.ClientException('Error temporal');
            }
            return jsonResponse({
              'codigo': 'TRZ-PDV-RETRY',
              'producto': 'Papa Recuperada',
              'total_eventos': 1,
              'eventos': const [
                {
                  'etapa': 'pdv',
                  'titulo': 'Disponible en punto de venta',
                  'fecha_fmt': '21/11/2026 10:00',
                },
              ],
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      // 1) 404 directo
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TrazabilidadPublicaScreen(
            codigo: 'TRZ-PDV-404',
            service: TrazabilidadPublicaService(api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Producto no encontrado'), findsOneWidget);

      // 2) Error de red + reintento exitoso
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TrazabilidadPublicaScreen(
            key: const ValueKey('retry-screen'),
            codigo: 'TRZ-PDV-RETRY',
            service: TrazabilidadPublicaService(api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Papa Recuperada'), findsOneWidget);
      expect(find.text('Disponible en punto de venta'), findsOneWidget);
    },
  );
}
