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

  const operarioPlantaProfile = {
    'usuarioid': 15,
    'nombre': 'Marco',
    'apellido': 'Salazar',
    'email': 'marco@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 5, 'name': 'planta'},
    ],
    'permissions': ['lote_produccion.view'],
  };

  const tareaLavado = {
    'asignacionetapaplantaid': 501,
    'orden': 1,
    'estado': 'pendiente',
    'creado_en': '2026-11-20T08:00:00Z',
    'completada_en': null,
    'observaciones': 'Revisar presión de agua',
    'proceso': {'procesoplantaid': 10, 'nombre': 'Lavado y desinfección'},
    'maquina': {
      'maquinaplantaid': 3,
      'nombre': 'Lavadora Industrial A1',
      'codigo': 'MAQ-01',
      'activo': true,
    },
    'lote_produccion': {
      'loteproduccionpedidoid': 90,
      'codigo_lote': 'LP-2026-090',
      'nombre': 'Lote Papa Andina',
      'producto': 'Papa prelavada',
      'fecha_creacion': '2026-11-20',
    },
    'resultado': null,
  };

  const tareaSecado = {
    'asignacionetapaplantaid': 502,
    'orden': 2,
    'estado': 'programada',
    'creado_en': '2026-11-20T08:05:00Z',
    'completada_en': null,
    'observaciones': null,
    'proceso': {'procesoplantaid': 11, 'nombre': 'Secado controlado'},
    'maquina': {
      'maquinaplantaid': 4,
      'nombre': 'Túnel de Secado B2',
      'codigo': 'MAQ-02',
      'activo': true,
    },
    'lote_produccion': {
      'loteproduccionpedidoid': 90,
      'codigo_lote': 'LP-2026-090',
      'nombre': 'Lote Papa Andina',
      'producto': 'Papa prelavada',
      'fecha_creacion': '2026-11-20',
    },
    'resultado': null,
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
    await storage.saveToken('1|planta-test');
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

  testWidgets(
    'El operario de planta consulta sus tareas asignadas y puede filtrarlas por estado',
    (tester) async {
      final requestedEstados = <String?>[];

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(operarioPlantaProfile);
        }
        if (request.url.path == '/api/planta/tareas' &&
            request.method == 'GET') {
          final estado = request.url.queryParameters['estado'];
          requestedEstados.add(estado);
          final all = [tareaLavado, tareaSecado];
          final filtered = estado == null
              ? all
              : all.where((t) => t['estado'] == estado).toList();
          return jsonResponse({
            'data': filtered,
            'meta': {
              'current_page': 1,
              'last_page': 1,
              'total': filtered.length,
            },
          });
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver tareas de planta'));
      await tester.pumpAndSettle();

      expect(find.text('Tareas de planta'), findsOneWidget);
      expect(find.text('Etapa 1'), findsOneWidget);
      expect(find.text('Lavado y desinfección'), findsOneWidget);
      expect(find.text('Etapa 2'), findsOneWidget);
      expect(find.text('Secado controlado'), findsOneWidget);
      expect(
        find.text('Máquina: Lavadora Industrial A1 (MAQ-01)'),
        findsOneWidget,
      );

      await tester.tap(find.text('Pendientes'));
      await tester.pumpAndSettle();

      expect(find.text('Lavado y desinfección'), findsOneWidget);
      expect(find.text('Secado controlado'), findsNothing);
      expect(requestedEstados, [null, 'pendiente']);
    },
  );

  testWidgets(
    'El detalle de la tarea identifica el proceso, la etapa, el lote y la máquina asignada',
    (tester) async {
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(operarioPlantaProfile);
        }
        if (request.url.path == '/api/planta/tareas' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [tareaLavado],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
          });
        }
        if (request.url.path == '/api/planta/tareas/501' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': tareaLavado,
            'meta': {
              'puede_completar': true,
              'requisito_pendiente': null,
              'maquinas_elegibles': [3],
              'parametros_requeridos': <Map<String, Object?>>[],
              'permite_parciales': false,
            },
          });
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver tareas de planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lavado y desinfección'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de tarea'), findsOneWidget);
      expect(find.text('Proceso y etapa'), findsOneWidget);
      expect(find.text('Lavado y desinfección'), findsAtLeastNWidgets(1));
      expect(find.text('Etapa 1'), findsOneWidget);
      expect(find.text('LP-2026-090 · Lote Papa Andina'), findsOneWidget);
      expect(find.text('Papa prelavada'), findsOneWidget);
      expect(find.text('Máquina asignada'), findsOneWidget);
      expect(find.text('Lavadora Industrial A1'), findsOneWidget);
      expect(find.text('MAQ-01'), findsOneWidget);
      expect(find.text('Disponible'), findsOneWidget);
    },
  );

  testWidgets(
    'Permite introducir y guardar los resultados medidos de una etapa autorizada',
    (tester) async {
      var completed = false;
      Map<String, dynamic>? sentBody;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(operarioPlantaProfile);
        }
        if (request.url.path == '/api/planta/tareas' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [
              completed
                  ? {...tareaLavado, 'estado': 'completada'}
                  : tareaLavado,
            ],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
          });
        }
        if (request.url.path == '/api/planta/tareas/501' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': completed
                ? {
                    ...tareaLavado,
                    'estado': 'completada',
                    'completada_en': '2026-11-21T11:30:00Z',
                    'resultado': {
                      'registroprocesomaquinaplantaid': 88,
                      'usuarioid': 15,
                      'fecha_registro': '2026-11-21T11:30:00Z',
                      'parametros': [
                        {
                          'variableestandarid': 12,
                          'nombre': 'Temperatura de lavado',
                          'unidad': '°C',
                          'valor': 65.5,
                          'valor_decimal': '65.5',
                        },
                      ],
                    },
                  }
                : tareaLavado,
            'meta': {
              'puede_completar': !completed,
              'requisito_pendiente': null,
              'maquinas_elegibles': completed ? <int>[] : [3],
              'parametros_requeridos': [
                {
                  'variableestandarid': 12,
                  'nombre': 'Temperatura de lavado',
                  'unidad': '°C',
                  'valor_minimo': 20,
                  'valor_maximo': 80,
                },
              ],
              'permite_parciales': false,
            },
          });
        }
        if (request.url.path ==
                '/api/planta/lotes-produccion/90/tareas/501/completar' &&
            request.method == 'POST') {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          completed = true;
          return jsonResponse({
            'data': {...tareaLavado, 'estado': 'completada'},
            'meta': {'puede_completar': false},
          });
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver tareas de planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lavado y desinfección'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('planta.param.12')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('planta.param.12')),
        '65.5',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('planta.tarea.completar')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('planta.tarea.completar')));
      await tester.pumpAndSettle();

      expect(find.text('¿Completar etapa de planta?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(sentBody, {
        'parametros': [
          {'variableestandarid': 12, 'valor': '65.5'},
        ],
      });
      expect(find.text('Completada'), findsOneWidget);
      expect(find.text('Resultados registrados'), findsOneWidget);
      expect(find.text('65.5 °C'), findsOneWidget);
    },
  );

  testWidgets(
    'Indica claramente el requisito o etapa faltante cuando no se puede continuar',
    (tester) async {
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(operarioPlantaProfile);
        }
        if (request.url.path == '/api/planta/tareas' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [tareaSecado],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
          });
        }
        if (request.url.path == '/api/planta/tareas/502' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': tareaSecado,
            'meta': {
              'puede_completar': false,
              'requisito_pendiente':
                  'Debe completarse primero la etapa 1 (Lavado y desinfección).',
              'maquinas_elegibles': <int>[],
              'parametros_requeridos': <Map<String, Object?>>[],
              'permite_parciales': false,
            },
          });
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver tareas de planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Secado controlado'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('planta.tarea.requisito')),
        findsOneWidget,
      );
      expect(find.text('No se puede completar todavía'), findsOneWidget);
      expect(
        find.text(
          'Debe completarse primero la etapa 1 (Lavado y desinfección).',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('planta.tarea.completar')),
        findsNothing,
      );
    },
  );

  testWidgets('Oculta tareas de planta a roles no autorizados', (tester) async {
    await startApp(tester, (request) async {
      if (request.url.path == '/api/me') {
        return jsonResponse({
          'usuarioid': 20,
          'nombre': 'Elena',
          'apellido': 'Vargas',
          'email': 'elena@example.test',
          'activo': true,
          'estado_cuenta': 'aprobado',
          'roles': [
            {'id': 6, 'name': 'jefe_planta'},
          ],
          'permissions': ['lote_produccion.view', 'lotes.view'],
        });
      }
      return jsonResponse({}, 404);
    });

    expect(find.text('Ver tareas de planta'), findsNothing);
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    expect(find.text('Tareas de planta'), findsNothing);
  });

  testWidgets(
    'Explica rechazos 422 y 409 del servidor conservando los datos ingresados',
    (tester) async {
      var submitAttempts = 0;
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse(operarioPlantaProfile);
        }
        if (request.url.path == '/api/planta/tareas' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [tareaLavado],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
          });
        }
        if (request.url.path == '/api/planta/tareas/501' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': tareaLavado,
            'meta': {
              'puede_completar': true,
              'requisito_pendiente': null,
              'maquinas_elegibles': [3],
              'parametros_requeridos': [
                {
                  'variableestandarid': 12,
                  'nombre': 'Temperatura de lavado',
                  'unidad': '°C',
                  'valor_minimo': 20,
                  'valor_maximo': 80,
                },
              ],
              'permite_parciales': false,
            },
          });
        }
        if (request.url.path ==
                '/api/planta/lotes-produccion/90/tareas/501/completar' &&
            request.method == 'POST') {
          submitAttempts++;
          if (submitAttempts == 1) {
            return jsonResponse({
              'message': 'Revisa las mediciones enviadas.',
              'errors': {
                'parametros.0.valor': [
                  'El valor está fuera del rango configurado para esta etapa.',
                ],
              },
            }, 422);
          }
          return jsonResponse({
            'message':
                'La etapa ya fue completada anteriormente con otros resultados.',
          }, 409);
        }
        return jsonResponse({}, 404);
      });

      await tester.tap(find.text('Ver tareas de planta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lavado y desinfección'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('planta.param.12')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('planta.param.12')),
        '70',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('planta.tarea.completar')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('planta.tarea.completar')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(
        find.text('El valor está fuera del rango configurado para esta etapa.'),
        findsOneWidget,
      );
      expect(find.text('70'), findsOneWidget);

      // Corrige el valor y reenvía -> 409 conflicto explicado + botón para actualizar estado.
      await tester.ensureVisible(find.byKey(const ValueKey('planta.param.12')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('planta.param.12')),
        '65',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('planta.tarea.completar')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('planta.tarea.completar')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'La etapa ya fue completada anteriormente con otros resultados.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('planta.tarea.recargar_tras_rechazo')),
        findsOneWidget,
      );
    },
  );
}
