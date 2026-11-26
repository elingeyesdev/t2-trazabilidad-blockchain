import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
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
    'email': 'jefe@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 2, 'name': 'jefe_agricultor'},
    ],
    'permissions': ['lotes.view', 'lotes.update'],
  };

  const workerProfile = {
    'usuarioid': 8,
    'nombre': 'Lucía',
    'apellido': 'Quispe',
    'email': 'lucia@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 3, 'name': 'agricultor'},
    ],
    'permissions': ['lotes.view', 'lotes.update'],
  };

  const lotsPayload = [
    {
      'loteid': 25,
      'nombre': 'Parcela Norte',
      'ubicacion': 'Sector A',
      'superficie': 2.5,
      'cultivo': {'cultivoid': 1, 'nombre': 'Papa'},
      'estado_tipo': {'estadolotetipoid': 2, 'nombre': 'Sembrado'},
    },
  ];

  const usersPayload = [
    {
      'usuarioid': 1,
      'nombre': 'Carlos',
      'apellido': 'Vega',
      'activo': true,
      'roles': [
        {'id': 2, 'name': 'jefe_agricultor'},
      ],
    },
    {
      'usuarioid': 8,
      'nombre': 'Lucía',
      'apellido': 'Quispe',
      'activo': true,
      'roles': [
        {'id': 3, 'name': 'agricultor'},
      ],
    },
    {
      'usuarioid': 9,
      'nombre': 'Admin',
      'apellido': 'Sistema',
      'activo': true,
      'roles': [
        {'id': 1, 'name': 'admin'},
      ],
    },
  ];

  const tiposPayload = [
    {'tipoactividadid': 3, 'nombre': 'Fertilización'},
    {'tipoactividadid': 4, 'nombre': 'Riego'},
  ];

  const prioridadesPayload = [
    {'prioridadid': 1, 'nombre': 'Baja'},
    {'prioridadid': 2, 'nombre': 'Alta'},
  ];

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
    await storage.saveToken('1|actividades-test');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(AgroFusionApp(apiClient: api));
    await tester.pumpAndSettle();
  }

  Future<void> openActividades(WidgetTester tester) async {
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Actividades'));
    await tester.tap(find.text('Actividades'));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'El jefe agrícola asigna una actividad con lote, responsable, fecha y prioridad',
    (tester) async {
      final activities = <Map<String, dynamic>>[];
      Map<String, dynamic>? sentBody;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(jefeProfile);
        if (request.url.path == '/api/lotes') return jsonResponse(lotsPayload);
        if (request.url.path == '/api/actividades/responsables') {
          return jsonResponse(usersPayload);
        }
        if (request.url.path == '/api/catalogos-operativos/tipoactividades') {
          return jsonResponse(tiposPayload);
        }
        if (request.url.path == '/api/catalogos-operativos/prioridades') {
          return jsonResponse(prioridadesPayload);
        }
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse(activities);
        }
        if (request.url.path == '/api/actividades' &&
            request.method == 'POST') {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          final created = {
            'actividadid': 51,
            'loteid': sentBody!['loteid'],
            'usuarioid': sentBody!['usuarioid'],
            'descripcion': 'Riego por goteo',
            'fecha_planificada': sentBody!['fecha_planificada'],
            'fechainicio': '2026-11-17T08:00:00Z',
            'fechafin': null,
            'observaciones': sentBody!['observaciones'],
            'lote': {
              'loteid': 25,
              'nombre': 'Parcela Norte',
              'cultivo': {'cultivoid': 1, 'nombre': 'Papa'},
            },
            'usuario': {
              'usuarioid': 8,
              'nombre': 'Lucía',
              'apellido': 'Quispe',
            },
            'tipo_actividad': {'tipoactividadid': 4, 'nombre': 'Riego'},
            'prioridad': {'prioridadid': 2, 'nombre': 'Alta'},
          };
          activities.add(created);
          return jsonResponse({'data': created}, 201);
        }
        if (request.url.path == '/api/actividades/51' &&
            request.method == 'GET') {
          return jsonResponse({'data': activities.first});
        }
        return jsonResponse({}, 404);
      });

      await openActividades(tester);
      await tester.tap(find.text('Asignar actividad'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('actividad.lote')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parcela Norte · Papa').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('actividad.tipo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riego').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('actividad.riego')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riego por goteo').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('actividad.responsable')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Admin Sistema'), findsNothing);
      await tester.tap(find.text('Lucía Quispe · Agricultor').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('actividad.prioridad')),
      );
      await tester.tap(find.byKey(const ValueKey('actividad.prioridad')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alta').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('actividad.fecha_planificada')),
        '2026-12-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('actividad.observaciones')),
        'Revisar mangueras del sector norte',
      );

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Asignar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Asignar actividad'));
      await tester.pumpAndSettle();
      expect(find.text('¿Asignar actividad?'), findsOneWidget);

      await tester.tap(find.text('Confirmar asignación'));
      await tester.pumpAndSettle();

      expect(sentBody?['loteid'], 25);
      expect(sentBody?['usuarioid'], 8);
      expect(sentBody?['tipoactividadid'], 4);
      expect(sentBody?['prioridadid'], 2);
      expect(sentBody?['fecha_planificada'], '2026-12-01');
      expect(sentBody?['observaciones'], 'Revisar mangueras del sector norte');
      expect(sentBody?['detalle_actividad_json'], contains('"key":"goteo"'));

      expect(find.text('Detalle de actividad'), findsOneWidget);
      expect(find.text('Riego por goteo'), findsOneWidget);
      expect(find.text('Lucía Quispe'), findsOneWidget);
      expect(find.text('01/12/2026'), findsOneWidget);
      expect(find.text('Alta'), findsOneWidget);
      expect(find.text('Revisar mangueras del sector norte'), findsOneWidget);
    },
  );

  testWidgets(
    'Muestra las validaciones de Laravel en el formulario de asignación sin perder datos',
    (tester) async {
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(jefeProfile);
        if (request.url.path == '/api/lotes') return jsonResponse(lotsPayload);
        if (request.url.path == '/api/actividades/responsables') {
          return jsonResponse(usersPayload);
        }
        if (request.url.path == '/api/catalogos-operativos/tipoactividades') {
          return jsonResponse(tiposPayload);
        }
        if (request.url.path == '/api/catalogos-operativos/prioridades') {
          return jsonResponse(prioridadesPayload);
        }
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([]);
        }
        if (request.url.path == '/api/actividades' &&
            request.method == 'POST') {
          return jsonResponse({
            'message': 'Revisa los datos enviados.',
            'errors': {
              'usuarioid': ['Seleccione un trabajador activo de su equipo.'],
              'tipoactividadid': [
                'La actividad no corresponde a la fase del lote.',
              ],
            },
          }, 422);
        }
        return jsonResponse({}, 404);
      });

      await openActividades(tester);
      await tester.tap(find.text('Asignar actividad'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('actividad.lote')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parcela Norte · Papa').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('actividad.tipo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertilización').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('actividad.responsable')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lucía Quispe · Agricultor').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('actividad.observaciones')),
        'Aplicar en la mañana',
      );

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Asignar actividad'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Asignar actividad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar asignación'));
      await tester.pumpAndSettle();

      expect(
        find.text('Seleccione un trabajador activo de su equipo.'),
        findsOneWidget,
      );
      expect(
        find.text('La actividad no corresponde a la fase del lote.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('actividad.observaciones')),
            )
            .controller!
            .text,
        'Aplicar en la mañana',
      );
    },
  );

  testWidgets(
    'El trabajador consulta sus tareas, filtra su estado y añade observaciones en el detalle',
    (tester) async {
      var task1 = <String, dynamic>{
        'actividadid': 11,
        'loteid': 25,
        'descripcion': 'Deshierbe sector norte',
        'fecha_planificada': '2026-11-20',
        'fechainicio': '2026-11-16T08:00:00Z',
        'fechafin': null,
        'observaciones': null,
        'lote': {'loteid': 25, 'nombre': 'Parcela Norte'},
        'usuario': {'usuarioid': 8, 'nombre': 'Lucía', 'apellido': 'Quispe'},
        'tipo_actividad': {'tipoactividadid': 2, 'nombre': 'Deshierbe'},
        'prioridad': {'prioridadid': 2, 'nombre': 'Alta'},
      };
      const task2 = <String, dynamic>{
        'actividadid': 12,
        'loteid': 25,
        'descripcion': 'Preparación de terreno',
        'fecha_planificada': '2026-11-10',
        'fechainicio': '2026-11-10T08:00:00Z',
        'fechafin': '2026-11-10T14:00:00Z',
        'observaciones': 'Terreno nivelado',
        'lote': {'loteid': 25, 'nombre': 'Parcela Norte'},
        'usuario': {'usuarioid': 8, 'nombre': 'Lucía', 'apellido': 'Quispe'},
        'tipo_actividad': {'tipoactividadid': 1, 'nombre': 'Preparación'},
        'prioridad': {'prioridadid': 1, 'nombre': 'Media'},
      };
      Map<String, dynamic>? sentPatch;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(workerProfile);
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([task1, task2]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({'data': task1});
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'PATCH') {
          sentPatch = jsonDecode(request.body) as Map<String, dynamic>;
          task1 = {...task1, 'observaciones': sentPatch!['observaciones']};
          return jsonResponse({'data': task1});
        }
        return jsonResponse({}, 404);
      });

      await openActividades(tester);
      expect(find.text('Asignar actividad'), findsNothing);
      expect(find.text('Deshierbe sector norte'), findsOneWidget);
      expect(find.text('Preparación de terreno'), findsOneWidget);

      await tester.tap(find.text('Completadas'));
      await tester.pumpAndSettle();
      expect(find.text('Preparación de terreno'), findsOneWidget);
      expect(find.text('Deshierbe sector norte'), findsNothing);

      await tester.tap(find.text('Pendientes'));
      await tester.pumpAndSettle();
      expect(find.text('Deshierbe sector norte'), findsOneWidget);
      expect(find.text('Preparación de terreno'), findsNothing);

      await tester.tap(find.text('Deshierbe sector norte'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Añadir observaciones'));
      await tester.tap(find.text('Añadir observaciones'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('actividad.observaciones')),
        'Avance al 80%, falta borde oeste.',
      );
      await tester.ensureVisible(find.text('Guardar observaciones'));
      await tester.tap(find.text('Guardar observaciones'));
      await tester.pumpAndSettle();
      expect(find.text('¿Guardar observaciones?'), findsOneWidget);

      await tester.tap(find.text('Confirmar observaciones'));
      await tester.pumpAndSettle();

      expect(sentPatch, {'observaciones': 'Avance al 80%, falta borde oeste.'});
      expect(find.text('Avance al 80%, falta borde oeste.'), findsOneWidget);
      expect(
        find.text('Las observaciones de la actividad se guardaron.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Oculta acciones de asignación y edición de notas a usuarios sin permiso',
    (tester) async {
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse({
            ...workerProfile,
            'permissions': ['lotes.view'],
          });
        }
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse([
            {
              'actividadid': 11,
              'loteid': 25,
              'descripcion': 'Deshierbe sector norte',
              'fechafin': null,
            },
          ]);
        }
        if (request.url.path == '/api/actividades/11' &&
            request.method == 'GET') {
          return jsonResponse({
            'actividadid': 11,
            'loteid': 25,
            'descripcion': 'Deshierbe sector norte',
            'fechafin': null,
          });
        }
        return jsonResponse({}, 404);
      });

      await openActividades(tester);
      expect(find.text('Asignar actividad'), findsNothing);

      await tester.tap(find.text('Deshierbe sector norte'));
      await tester.pumpAndSettle();
      expect(find.text('Añadir observaciones'), findsNothing);
      expect(find.text('Editar observaciones'), findsNothing);

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('${AppModule.actividades.route}/nueva')
          .ignore();
      await tester.pumpAndSettle();
      expect(find.text('Acceso no autorizado'), findsOneWidget);
    },
  );

  testWidgets(
    'El jefe agrícola carga su equipo desde actividades/responsables aunque usuarios devuelva 403',
    (tester) async {
      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(jefeProfile);
        if (request.url.path == '/api/actividades' && request.method == 'GET') {
          return jsonResponse(const []);
        }
        if (request.url.path == '/api/lotes' && request.method == 'GET') {
          return jsonResponse(lotsPayload);
        }
        if (request.url.path == '/api/usuarios' && request.method == 'GET') {
          return jsonResponse({'message': 'Forbidden'}, 403);
        }
        if (request.url.path == '/api/actividades/responsables' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [
              {
                'usuarioid': 8,
                'nombre': 'Lucía',
                'apellido': 'Quispe',
                'role': 'agricultor',
                'activo': true,
              },
            ],
          });
        }
        if (request.url.path == '/api/tipoactividades') {
          return jsonResponse(tiposPayload);
        }
        if (request.url.path == '/api/prioridades') {
          return jsonResponse(prioridadesPayload);
        }
        return jsonResponse({}, 404);
      });

      await openActividades(tester);
      await tester.tap(find.text('Asignar actividad'));
      await tester.pumpAndSettle();

      expect(
        find.text('No tienes permiso para realizar esta acción.'),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('actividad.responsable')));
      await tester.pumpAndSettle();
      expect(find.text('Lucía Quispe · Agricultor'), findsWidgets);
    },
  );
}
