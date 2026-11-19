import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/widgets/location_input_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();

  const jefeProfile = {
    'usuarioid': 1,
    'nombre': 'Carlos',
    'apellido': 'Vega',
    'email': 'carlos@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 2, 'name': 'jefe_agricultor'},
    ],
    'permissions': [
      'lotes.view',
      'lotes.create',
      'lotes.update',
      'inventario.view',
    ],
  };

  const seedsPayload = [
    {
      'insumoid': 12,
      'nombre': 'Semilla de Papa',
      'stock': 120,
      'tipo': {'tipoinsumoid': 1, 'nombre': 'Material de Siembra'},
      'unidad_medida': {
        'unidadmedidaid': 1,
        'nombre': 'Kilogramo',
        'abreviatura': 'kg',
      },
    },
    {
      'insumoid': 14,
      'nombre': 'Semilla de Maíz',
      'stock': 80,
      'tipo': {'tipoinsumoid': 1, 'nombre': 'Material de Siembra'},
      'unidad_medida': {
        'unidadmedidaid': 1,
        'nombre': 'Kilogramo',
        'abreviatura': 'kg',
      },
    },
    {
      'insumoid': 99,
      'nombre': 'Fertilizante NPK',
      'stock': 50,
      'tipo': {'tipoinsumoid': 2, 'nombre': 'Fertilizantes'},
      'unidad_medida': {
        'unidadmedidaid': 1,
        'nombre': 'Kilogramo',
        'abreviatura': 'kg',
      },
    },
  ];

  const existingLot = {
    'loteid': 7,
    'usuarioid': 1,
    'nombre': 'Parcela Norte',
    'ubicacion': 'Sector alto',
    'superficie': 2.5,
    'insumosemillaid': 12,
    'cantidad_semilla_planificada': 25,
    'codigo_trazabilidad': 'TRAZ-20261116-0007',
    'latitud': -17.78,
    'longitud': -63.18,
    'usuario': {'usuarioid': 1, 'nombre': 'Carlos', 'apellido': 'Vega'},
    'cultivo': {'cultivoid': 3, 'nombre': 'Papa'},
    'estado_tipo': {'estadolotetipoid': 1, 'nombre': 'Planificación'},
    'insumo_semilla': {'insumoid': 12, 'nombre': 'Semilla de Papa'},
  };

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<void> startApp(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    Future<DeviceLocation?> Function()? requestLocation,
  }) async {
    await storage.saveToken('1|lotes-form');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      AgroFusionApp(apiClient: api, requestLocation: requestLocation),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openLotes(WidgetTester tester) async {
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lotes'));
    await tester.tap(find.text('Lotes'));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Crea un lote con semilla, superficie y ubicación del dispositivo y muestra el detalle guardado',
    (tester) async {
      final lots = <Map<String, dynamic>>[];
      Map<String, dynamic>? sentCreateBody;

      await startApp(
        tester,
        (request) async {
          if (request.url.path == '/api/me') return jsonResponse(jefeProfile);
          if (request.url.path == '/api/insumos') {
            return jsonResponse(seedsPayload);
          }
          if (request.url.path == '/api/lotes' && request.method == 'GET') {
            return jsonResponse(lots);
          }
          if (request.url.path == '/api/lotes' && request.method == 'POST') {
            sentCreateBody = jsonDecode(request.body) as Map<String, dynamic>;
            final created = {
              'loteid': 25,
              'usuarioid': 1,
              'nombre': sentCreateBody!['nombre'],
              'superficie': sentCreateBody!['superficie'],
              'insumosemillaid': sentCreateBody!['insumosemillaid'],
              'ubicacion': 'Camino Norte km 4',
              'latitud': sentCreateBody!['latitud'],
              'longitud': sentCreateBody!['longitud'],
              'codigo_trazabilidad': 'TRAZ-20261116-0025',
              'usuario': {
                'usuarioid': 1,
                'nombre': 'Carlos',
                'apellido': 'Vega',
              },
              'cultivo': {'cultivoid': 3, 'nombre': 'Papa'},
              'estado_tipo': {'estadolotetipoid': 1, 'nombre': 'Planificación'},
              'insumo_semilla': {'insumoid': 12, 'nombre': 'Semilla de Papa'},
            };
            lots.add(created);
            return jsonResponse({'data': created}, 201);
          }
          if (request.url.path == '/api/lotes/25' && request.method == 'GET') {
            return jsonResponse({'data': lots.first});
          }
          return jsonResponse({}, 404);
        },
        requestLocation: () async => const DeviceLocation(
          latitude: -17.7516,
          longitude: -63.2367,
          address: 'Urubó, Santa Cruz',
        ),
      );

      await openLotes(tester);
      await tester.tap(find.text('Nuevo lote'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('lote.nombre')),
        'Parcela San Juan',
      );

      await tester.tap(find.byKey(const ValueKey('lote.semilla')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fertilizante NPK'), findsNothing);
      await tester.tap(find.text('Semilla de Papa (120 kg disp.)').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('lote.superficie')),
        '3.5',
      );

      await tester.ensureVisible(find.text('Usar ubicación actual'));
      await tester.tap(find.text('Usar ubicación actual'));
      await tester.pumpAndSettle();
      expect(
        find.text('Coordenadas registradas: -17.7516, -63.2367'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Crear lote'));
      await tester.tap(find.text('Crear lote'));
      await tester.pumpAndSettle();
      expect(find.text('¿Crear lote?'), findsOneWidget);

      await tester.tap(find.text('Confirmar registro'));
      await tester.pumpAndSettle();

      expect(sentCreateBody?['nombre'], 'Parcela San Juan');
      expect(sentCreateBody?['insumosemillaid'], 12);
      expect(sentCreateBody?['superficie'], 3.5);
      expect(sentCreateBody?['ubicacion'], 'Urubó, Santa Cruz');
      expect(sentCreateBody?['latitud'], closeTo(-17.7516, 0.0001));
      expect(sentCreateBody?['longitud'], closeTo(-63.2367, 0.0001));

      expect(find.text('Detalle del lote'), findsOneWidget);
      expect(find.text('Parcela San Juan'), findsOneWidget);
      expect(find.text('Camino Norte km 4'), findsOneWidget);
      expect(find.text('3,50 hectáreas'), findsOneWidget);
      expect(find.text('TRAZ-20261116-0025'), findsOneWidget);
      expect(find.text('Semilla de Papa'), findsOneWidget);
    },
  );

  testWidgets(
    'Denegar permiso de ubicación permite introducir la ubicación manualmente al crear un lote',
    (tester) async {
      Map<String, dynamic>? sentCreateBody;
      var savedLot = <String, dynamic>{};

      await startApp(
        tester,
        (request) async {
          if (request.url.path == '/api/me') return jsonResponse(jefeProfile);
          if (request.url.path == '/api/insumos') {
            return jsonResponse(seedsPayload);
          }
          if (request.url.path == '/api/lotes' && request.method == 'GET') {
            return jsonResponse(savedLot.isEmpty ? [] : [savedLot]);
          }
          if (request.url.path == '/api/lotes' && request.method == 'POST') {
            sentCreateBody = jsonDecode(request.body) as Map<String, dynamic>;
            savedLot = {
              'loteid': 31,
              'nombre': sentCreateBody!['nombre'],
              'superficie': sentCreateBody!['superficie'],
              'insumosemillaid': sentCreateBody!['insumosemillaid'],
              'ubicacion': sentCreateBody!['ubicacion'],
              'cultivo': {'cultivoid': 4, 'nombre': 'Maíz'},
              'estado_tipo': {'estadolotetipoid': 1, 'nombre': 'Planificación'},
              'insumo_semilla': {'insumoid': 14, 'nombre': 'Semilla de Maíz'},
            };
            return jsonResponse({'data': savedLot}, 201);
          }
          if (request.url.path == '/api/lotes/31' && request.method == 'GET') {
            return jsonResponse({'data': savedLot});
          }
          return jsonResponse({}, 404);
        },
        requestLocation: () async => throw PlatformException(
          code: 'location_permission_denied',
          message: 'Permiso denegado',
        ),
      );

      await openLotes(tester);
      await tester.tap(find.text('Nuevo lote'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('lote.nombre')),
        'Parcela Manual',
      );
      await tester.tap(find.byKey(const ValueKey('lote.semilla')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semilla de Maíz (80 kg disp.)').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lote.superficie')),
        '1.75',
      );

      await tester.ensureVisible(find.text('Usar ubicación actual'));
      await tester.tap(find.text('Usar ubicación actual'));
      await tester.pumpAndSettle();
      expect(find.text('Permiso de ubicación denegado'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('location.ubicacion')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.ubicacion')),
        'Comunidad El Carmen, Sector Sur',
      );

      await tester.ensureVisible(find.text('Crear lote'));
      await tester.tap(find.text('Crear lote'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar registro'));
      await tester.pumpAndSettle();

      expect(sentCreateBody?['ubicacion'], 'Comunidad El Carmen, Sector Sur');
      expect(find.text('Parcela Manual'), findsOneWidget);
      expect(find.text('Comunidad El Carmen, Sector Sur'), findsOneWidget);
    },
  );

  testWidgets(
    'Edita un lote enviando solo los cambios, conserva los datos sin modificar y actualiza el detalle',
    (tester) async {
      var currentLot = Map<String, dynamic>.from(existingLot);
      Map<String, dynamic>? sentPatchBody;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(jefeProfile);
        if (request.url.path == '/api/insumos') {
          return jsonResponse(seedsPayload);
        }
        if (request.url.path == '/api/lotes' && request.method == 'GET') {
          return jsonResponse([currentLot]);
        }
        if (request.url.path == '/api/lotes/7' && request.method == 'GET') {
          return jsonResponse({'data': currentLot});
        }
        if (request.url.path == '/api/lotes/7' && request.method == 'PATCH') {
          sentPatchBody = jsonDecode(request.body) as Map<String, dynamic>;
          currentLot = {...currentLot, ...sentPatchBody!};
          return jsonResponse({'data': currentLot});
        }
        return jsonResponse({}, 404);
      });

      await openLotes(tester);
      await tester.tap(find.text('Parcela Norte'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Editar lote'));
      await tester.pumpAndSettle();

      expect(
        find.text('Coordenadas registradas: -17.7800, -63.1800'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('lote.nombre')),
        'Parcela Norte Corregida',
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.ubicacion')),
        'Sector alto remodelado',
      );

      await tester.ensureVisible(find.text('Guardar cambios'));
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar cambios'));
      await tester.pumpAndSettle();

      expect(sentPatchBody, {
        'nombre': 'Parcela Norte Corregida',
        'ubicacion': 'Sector alto remodelado',
      });
      expect(sentPatchBody?.containsKey('superficie'), isFalse);
      expect(sentPatchBody?.containsKey('insumosemillaid'), isFalse);
      expect(sentPatchBody?.containsKey('latitud'), isFalse);

      expect(find.text('Parcela Norte Corregida'), findsOneWidget);
      expect(find.text('Sector alto remodelado'), findsOneWidget);
      expect(find.text('2,50 hectáreas'), findsOneWidget);
      expect(find.text('TRAZ-20261116-0007'), findsOneWidget);

      await tester.tap(find.text('Volver a la lista'));
      await tester.pumpAndSettle();
      expect(find.text('Parcela Norte Corregida'), findsOneWidget);
    },
  );

  testWidgets(
    'Conserva los datos introducidos ante errores de validación 422 y fallos de conexión',
    (tester) async {
      var attempt = 0;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(jefeProfile);
        if (request.url.path == '/api/insumos') {
          return jsonResponse(seedsPayload);
        }
        if (request.url.path == '/api/lotes' && request.method == 'GET') {
          return jsonResponse([]);
        }
        if (request.url.path == '/api/lotes' && request.method == 'POST') {
          attempt++;
          if (attempt == 1) {
            return jsonResponse({
              'message': 'Revisa los datos enviados.',
              'errors': {
                'superficie': ['No hay stock suficiente para 10 ha.'],
                'ubicacion': ['La ubicación debe ser más específica.'],
              },
            }, 422);
          }
          throw http.ClientException('offline');
        }
        return jsonResponse({}, 404);
      });

      await openLotes(tester);
      await tester.tap(find.text('Nuevo lote'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('lote.nombre')),
        'Parcela Con Errores',
      );
      await tester.tap(find.byKey(const ValueKey('lote.semilla')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semilla de Papa (120 kg disp.)').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lote.superficie')),
        '10',
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.ubicacion')),
        'Norte',
      );

      await tester.ensureVisible(find.text('Crear lote'));
      await tester.tap(find.text('Crear lote'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar registro'));
      await tester.pumpAndSettle();

      expect(find.text('No hay stock suficiente para 10 ha.'), findsOneWidget);
      expect(
        find.text('La ubicación debe ser más específica.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('lote.nombre')))
            .controller!
            .text,
        'Parcela Con Errores',
      );

      await tester.enterText(
        find.byKey(const ValueKey('lote.superficie')),
        '2.0',
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.ubicacion')),
        'Norte, Parcela 5',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Crear lote'));
      await tester.tap(find.text('Crear lote'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar registro'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No se pudo conectar con el servidor. Revisa tu conexión e intenta de nuevo.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('location.ubicacion')),
            )
            .controller!
            .text,
        'Norte, Parcela 5',
      );
      expect(attempt, 2);
    },
  );

  testWidgets(
    'Oculta crear y editar a usuarios sin permiso de gestión y bloquea lotes cosechados',
    (tester) async {
      final closedLot = {
        ...existingLot,
        'estado_tipo': {'estadolotetipoid': 5, 'nombre': 'Cosechado'},
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse({
            ...jefeProfile,
            'roles': [
              {'id': 1, 'name': 'admin'},
            ],
            'permissions': ['lotes.view', 'lotes.create', 'lotes.update'],
          });
        }
        if (request.url.path == '/api/lotes' && request.method == 'GET') {
          return jsonResponse([closedLot]);
        }
        if (request.url.path == '/api/lotes/7' && request.method == 'GET') {
          return jsonResponse({'data': closedLot});
        }
        return jsonResponse({}, 404);
      });

      await openLotes(tester);
      expect(find.text('Nuevo lote'), findsNothing);

      await tester.tap(find.text('Parcela Norte'));
      await tester.pumpAndSettle();
      expect(find.text('Editar lote'), findsNothing);

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('${AppModule.lotes.route}/nuevo')
          .ignore();
      await tester.pumpAndSettle();
      expect(find.text('Acceso no autorizado'), findsOneWidget);
    },
  );
}
