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

  const operarioProfile = {
    'usuarioid': 15,
    'nombre': 'Mateo',
    'apellido': 'Salazar',
    'email': 'mateo@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 5, 'name': 'planta'},
    ],
    'permissions': ['lote_produccion.view'],
  };

  const tareaRow = {
    'asignacionetapaplantaid': 31,
    'orden': 1,
    'estado': 'pendiente',
    'proceso': {'procesoplantaid': 4, 'nombre': 'Lavado y selección'},
    'maquina': {
      'maquinaplantaid': 9,
      'nombre': 'Lavadora Industrial L-02',
      'codigo': 'MAQ-L02',
      'activo': true,
    },
    'lote_produccion': {
      'loteproduccionpedidoid': 88,
      'codigo_lote': 'LP-2026-088',
      'nombre': 'Hojuelas de Papa Premium',
      'producto': 'Hojuelas de Papa',
      'fecha_creacion': '2026-11-21',
    },
    'resultado': null,
  };

  const recorridoPayload = {
    'nivel': 'lote_produccion',
    'lote_produccion': {
      'id': 88,
      'codigo': 'LP-2026-088',
      'nombre': 'Hojuelas de Papa Premium',
    },
    'origenes': [
      {
        'consumo_id': 501,
        'insumo_id': 12,
        'insumo': 'Papa Huaycha',
        'almacen_id': 8,
        'referencia_partida': 'MP-2026-025',
        'materiaprimaloteid': 40,
        'inventario_presentacion_loteid': null,
        'cantidad_consumida': '120.500000',
        'cantidad_unidades_consumidas': null,
        'presentacion': null,
        'unidad_presentacion': null,
        'unidad_registrada': 'kg',
        'unidad_catalogo_actual': 'kg',
        'movimiento_consumo_id': 901,
        'cantidad_recibida': '150.000000',
        'unidad_recepcion': 'kg',
        'recepcion': {
          'pedidoid': 60,
          'detallepedidoid': 41,
          'fecha': '2026-11-20T14:00:00Z',
        },
        'origen_agricola': {'loteid': 25, 'produccionid': 71},
        'origen_industrial_id': null,
        'antecedente_restringido': false,
      },
      {
        'consumo_id': 502,
        'insumo_id': 19,
        'insumo': 'Papa prelavada',
        'almacen_id': 8,
        'referencia_partida': 'IND-077',
        'materiaprimaloteid': null,
        'inventario_presentacion_loteid': 55,
        'cantidad_consumida': '40.000000',
        'cantidad_unidades_consumidas': '4.000000',
        'presentacion': 'Caja 10 kg',
        'unidad_presentacion': 'cajas',
        'unidad_registrada': 'kg',
        'unidad_catalogo_actual': 'kg',
        'movimiento_consumo_id': 902,
        'cantidad_recibida': null,
        'unidad_recepcion': null,
        'recepcion': null,
        'origen_agricola': null,
        'origen_industrial_id': 77,
        'antecedente_restringido': false,
      },
    ],
    'productos_obtenidos': [
      {
        'partida_id': 301,
        'insumo_id': 90,
        'producto': 'Hojuelas de Papa',
        'presentacion_id': 15,
        'presentacion': 'Bolsa 500 g',
      },
    ],
    'ingresos_produccion': [
      {
        'almacenaje_id': 601,
        'insumo_id': 90,
        'producto': 'Hojuelas de Papa',
        'presentacion_id': 15,
        'presentacion': 'Bolsa 500 g',
        'partida_id': 301,
        'cantidad_ingresada': '180.000000',
        'unidad': 'bolsas',
        'cantidad_kg': '90.000000',
        'almacen_id': 11,
        'almacen': 'Almacén Producto Terminado Norte',
        'fecha': '2026-11-21T16:30:00Z',
        'estado': 'Ingreso registrado',
      },
    ],
    'ubicaciones_actuales': [
      {
        'partida_id': 301,
        'insumo_id': 90,
        'producto': 'Hojuelas de Papa',
        'presentacion_id': 15,
        'presentacion': 'Bolsa 500 g',
        'unidad': 'bolsas',
        'cantidad_actual': '140.000000',
        'cantidad_actual_kg': '70.000000',
        'almacen_id': 11,
        'almacen': 'Almacén Producto Terminado Norte',
      },
    ],
    'restricciones': {
      'origenes': false,
      'destinos': false,
      'ubicaciones_actuales': false,
    },
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
    await storage.saveToken('1|procesamiento-test');
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

  testWidgets('La ficha de un procesamiento muestra sus lotes de origen', (
    tester,
  ) async {
    await startApp(tester, (request) async {
      if (request.url.path == '/api/me') {
        return jsonResponse(operarioProfile);
      }
      if (request.url.path == '/api/planta/tareas' && request.method == 'GET') {
        return jsonResponse({
          'data': [tareaRow],
          'meta': {'current_page': 1, 'last_page': 1},
        });
      }
      if (request.url.path == '/api/planta/tareas/31' &&
          request.method == 'GET') {
        return jsonResponse({'data': tareaRow});
      }
      if (request.url.path == '/api/planta/lotes-produccion/88' &&
          request.method == 'GET') {
        return jsonResponse({'data': recorridoPayload});
      }
      return jsonResponse({}, 404);
    });

    await tester.tap(find.text('Ver tareas de planta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lavado y selección'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('tarea.ver_origen_resultado')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tarea.ver_origen_resultado')));
    await tester.pumpAndSettle();

    expect(find.text('Lote de producción #88'), findsOneWidget);
    expect(find.text('Hojuelas de Papa Premium'), findsOneWidget);
    expect(find.text('Código: LP-2026-088'), findsOneWidget);
    expect(find.text('Lotes de origen'), findsOneWidget);
    expect(find.text('Papa Huaycha'), findsOneWidget);
    expect(find.text('Lote agrícola #25 · Cosecha #71'), findsOneWidget);
    expect(find.text('MP-2026-025'), findsOneWidget);
    expect(find.text('Papa prelavada'), findsOneWidget);
    expect(find.text('Lote de producción #77'), findsOneWidget);
    expect(find.text('IND-077'), findsOneWidget);
  });

  testWidgets(
    'Muestra las cantidades de materia prima utilizadas con sus unidades y separa la cantidad recibida',
    (tester) async {
      final historicalPayload = {
        ...recorridoPayload,
        'origenes': [
          ...(recorridoPayload['origenes'] as List),
          {
            'consumo_id': 503,
            'insumo_id': 21,
            'insumo': 'Aceite vegetal',
            'almacen_id': 8,
            'referencia_partida': 'HIST-001',
            'materiaprimaloteid': 49,
            'inventario_presentacion_loteid': null,
            'cantidad_consumida': '12.250000',
            'cantidad_unidades_consumidas': null,
            'presentacion': null,
            'unidad_presentacion': null,
            'unidad_registrada': null,
            'unidad_catalogo_actual': 'L',
            'movimiento_consumo_id': null,
            'cantidad_recibida': null,
            'unidad_recepcion': null,
            'recepcion': null,
            'origen_agricola': null,
            'origen_industrial_id': null,
            'antecedente_restringido': false,
          },
        ],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(operarioProfile);
        }
        if (request.url.path == '/api/planta/tareas' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [tareaRow],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/planta/tareas/31' &&
            request.method == 'GET') {
          return jsonResponse({'data': tareaRow});
        }
        if (request.url.path == '/api/planta/lotes-produccion/88' &&
            request.method == 'GET') {
          return jsonResponse({'data': historicalPayload});
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver tareas de planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lavado y selección'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('tarea.ver_origen_resultado')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('tarea.ver_origen_resultado')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cantidad utilizada'), findsNWidgets(3));
      expect(find.text('120.5 kg'), findsOneWidget);
      expect(find.text('Cantidad recibida en recepción'), findsOneWidget);
      expect(find.text('150 kg'), findsOneWidget);
      expect(find.text('40 kg'), findsOneWidget);
      expect(find.text('4 cajas'), findsOneWidget);
      expect(
        find.text('12.25 (unidad histórica desconocida; catálogo actual: L)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Identifica los productos obtenidos y sus cantidades', (
    tester,
  ) async {
    final payloadWithLegacy = {
      ...recorridoPayload,
      'productos_obtenidos': [
        ...(recorridoPayload['productos_obtenidos'] as List),
        {
          'partida_id': 302,
          'insumo_id': 91,
          'producto': 'Harina de Papa',
          'presentacion_id': 16,
          'presentacion': 'Saco 25 kg',
        },
      ],
    };

    await startApp(tester, (request) async {
      if (request.url.path == '/api/me') {
        return jsonResponse(operarioProfile);
      }
      if (request.url.path == '/api/planta/tareas' && request.method == 'GET') {
        return jsonResponse({
          'data': [tareaRow],
          'meta': {'current_page': 1, 'last_page': 1},
        });
      }
      if (request.url.path == '/api/planta/tareas/31' &&
          request.method == 'GET') {
        return jsonResponse({'data': tareaRow});
      }
      if (request.url.path == '/api/planta/lotes-produccion/88' &&
          request.method == 'GET') {
        return jsonResponse({'data': payloadWithLegacy});
      }
      return jsonResponse({}, 404);
    });

    await tester.tap(find.text('Ver tareas de planta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lavado y selección'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('tarea.ver_origen_resultado')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tarea.ver_origen_resultado')));
    await tester.pumpAndSettle();

    final producto301 = find.byKey(
      const ValueKey('procesamiento.producto.301'),
    );
    expect(find.text('Productos obtenidos'), findsOneWidget);
    expect(
      find.descendant(
        of: producto301,
        matching: find.text('Hojuelas de Papa · Bolsa 500 g'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: producto301, matching: find.text('Partida #301')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: producto301, matching: find.text('180 bolsas')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: producto301, matching: find.text('90 kg')),
      findsOneWidget,
    );
    expect(find.text('Harina de Papa · Saco 25 kg'), findsOneWidget);
    expect(find.text('Partida #302'), findsOneWidget);
    expect(
      find.text('Cantidad original no conservada en este registro'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Muestra el almacén de ingreso original y la ubicación con saldo actual',
    (tester) async {
      final transferredPayload = {
        ...recorridoPayload,
        'ubicaciones_actuales': [
          {
            'partida_id': 301,
            'insumo_id': 90,
            'producto': 'Hojuelas de Papa',
            'presentacion_id': 15,
            'presentacion': 'Bolsa 500 g',
            'unidad': 'bolsas',
            'cantidad_actual': '140.000000',
            'cantidad_actual_kg': '70.000000',
            'almacen_id': 14,
            'almacen': 'Almacén Despacho Central',
          },
        ],
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(operarioProfile);
        }
        if (request.url.path == '/api/planta/tareas' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [tareaRow],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/planta/tareas/31' &&
            request.method == 'GET') {
          return jsonResponse({'data': tareaRow});
        }
        if (request.url.path == '/api/planta/lotes-produccion/88' &&
            request.method == 'GET') {
          return jsonResponse({'data': transferredPayload});
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver tareas de planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lavado y selección'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('tarea.ver_origen_resultado')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('tarea.ver_origen_resultado')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Almacenamiento e ingreso original'), findsOneWidget);
      expect(find.text('Almacén Producto Terminado Norte'), findsOneWidget);
      expect(find.text('2026-11-21T16:30:00Z'), findsOneWidget);
      expect(find.text('Ingreso registrado'), findsOneWidget);

      expect(find.text('Ubicación y saldo actual'), findsOneWidget);
      expect(find.text('Almacén Despacho Central'), findsOneWidget);
      expect(find.text('140 bolsas'), findsOneWidget);
      expect(find.text('70 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'Respeta los permisos del usuario mostrando avisos de restricción y 404 en procesos ajenos',
    (tester) async {
      final restrictedPayload = {
        'nivel': 'lote_produccion',
        'lote_produccion': {
          'id': 88,
          'codigo': 'LP-2026-088',
          'nombre': 'Hojuelas de Papa Premium',
        },
        'origenes': [
          {
            'consumo_id': 510,
            'insumo_id': 12,
            'insumo': 'Papa Huaycha',
            'almacen_id': 8,
            'referencia_partida': 'MP-RES-01',
            'materiaprimaloteid': 40,
            'inventario_presentacion_loteid': null,
            'cantidad_consumida': '50.000000',
            'cantidad_unidades_consumidas': null,
            'presentacion': null,
            'unidad_presentacion': null,
            'unidad_registrada': 'kg',
            'unidad_catalogo_actual': 'kg',
            'movimiento_consumo_id': null,
            'cantidad_recibida': null,
            'unidad_recepcion': null,
            'recepcion': null,
            'origen_agricola': null,
            'origen_industrial_id': null,
            'antecedente_restringido': true,
          },
        ],
        'productos_obtenidos': const <Map<String, Object?>>[],
        'ingresos_produccion': const <Map<String, Object?>>[],
        'ubicaciones_actuales': const <Map<String, Object?>>[],
        'restricciones': {
          'origenes': true,
          'destinos': true,
          'ubicaciones_actuales': true,
        },
      };

      final foreignTarea = {
        ...tareaRow,
        'asignacionetapaplantaid': 32,
        'proceso': {'procesoplantaid': 5, 'nombre': 'Empaque final'},
        'lote_produccion': {
          'loteproduccionpedidoid': 99,
          'codigo_lote': 'LP-2026-099',
          'nombre': 'Proceso ajeno',
          'producto': 'Papa',
          'fecha_creacion': '2026-11-21',
        },
      };

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(operarioProfile);
        }
        if (request.url.path == '/api/planta/tareas' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [tareaRow, foreignTarea],
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/planta/tareas/31' &&
            request.method == 'GET') {
          return jsonResponse({'data': tareaRow});
        }
        if (request.url.path == '/api/planta/tareas/32' &&
            request.method == 'GET') {
          return jsonResponse({'data': foreignTarea});
        }
        if (request.url.path == '/api/planta/lotes-produccion/88' &&
            request.method == 'GET') {
          return jsonResponse({'data': restrictedPayload});
        }
        if (request.url.path == '/api/planta/lotes-produccion/99' &&
            request.method == 'GET') {
          return jsonResponse({'message': 'No encontrado.'}, 404);
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver tareas de planta'));
      await tester.pumpAndSettle();

      // Proceso 88 con relaciones restringidas.
      await tester.tap(find.text('Lavado y selección'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('tarea.ver_origen_resultado')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('tarea.ver_origen_resultado')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Antecedente restringido por permisos'), findsOneWidget);
      expect(
        find.textContaining('materias primas de este proceso pertenece'),
        findsOneWidget,
      );
      expect(
        find.textContaining('destinos de ingreso pertenece'),
        findsOneWidget,
      );
      expect(
        find.textContaining('ubicaciones o saldos actuales pertenece'),
        findsOneWidget,
      );

      // Vuelve al listado y abre un proceso ajeno (404).
      await tester.tap(find.byKey(const ValueKey('procesamiento.volver')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volver a tareas de planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empaque final'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('tarea.ver_origen_resultado')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('tarea.ver_origen_resultado')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Procesamiento no disponible'), findsOneWidget);
    },
  );
}
