import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/models/field_record_info.dart';
import 'package:agrofusion_mobile/navigation/app_module.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const lot = {
  'loteid': 7,
  'nombre': 'Parcela Los Pinos',
  'cultivo': {'nombre': 'Maíz'},
  'insumo_semilla': {'nombre': 'Maíz amarillo'},
  'estado_tipo': {'nombre': 'sembrado'},
  'usuario': {
    'nombre': 'Carmen',
    'apellido': 'Lima',
    'passwordhash': 'privado',
  },
  'ubicacion': 'Sector alto',
  'superficie': 1000.2,
  'fechasiembra': '2026-10-20T00:00:00+02:00',
  'codigo_trazabilidad': 'AF-007',
};
const activity = {
  'actividadid': 11,
  'descripcion': 'Riego de Los Pinos',
  'loteid': 7,
  'lote': {
    'nombre': 'Parcela Los Pinos',
    'cultivo': {'nombre': 'Maíz'},
  },
  'usuario': {'nombre': 'Carmen', 'apellido': 'Lima'},
  'tipo_actividad': {'nombre': 'Riego'},
  'prioridad': {'nombre': 'Alta'},
  'fecha_planificada': '2026-10-29T00:00:00+02:00',
  'fechainicio': null,
  'fechafin': null,
  'observaciones': 'Revisar los surcos del sector norte.',
};

void main() {
  test(
    'El lote muestra los mismos nombres, unidades y fecha de siembra de la web',
    () {
      final info = FieldRecordInfo.lote(lot);
      expect(info.status, 'Sembrado');
      expect(info.summary['Cultivo'], 'Maíz amarillo');
      expect(info.details['Responsable'], 'Carmen Lima');
      expect(info.details['Superficie'], '1.000,20 hectáreas');
      expect(info.details['Fecha de siembra'], '20/10/2026');
      expect(info.details.values.join(' '), isNot(contains('privado')));
      expect(
        FieldRecordInfo.lote({...lot, 'superficie': 1}).details['Superficie'],
        '1,00 hectárea',
      );
      expect(
        FieldRecordInfo.lote({
          ...lot,
          'insumo_semilla': null,
        }).summary['Cultivo'],
        'Maíz',
      );
    },
  );

  test(
    'Un total pendiente desconocido se distingue de cero actividades pendientes',
    () {
      expect(FieldRecordInfo.lote(lot).summary['Pendientes'], 'No disponible');
      expect(
        FieldRecordInfo.lote({...lot, 'actividades': []}).summary['Pendientes'],
        '0',
      );
      expect(
        FieldRecordInfo.lote({
          ...lot,
          'actividades_pendientes': 4,
        }).summary['Pendientes'],
        '4',
      );
      final counted = FieldRecordInfo.lote({
        ...lot,
        'actividades': [
          {'fechafin': null},
          {'fechafin': '2026-10-28T12:00:00Z'},
          {'fechafin': null},
        ],
      });
      expect(counted.details['Actividades pendientes'], '2');
      expect(
        FieldRecordInfo.lote({
          ...lot,
          'actividades': [
            {'actividadid': 1},
          ],
        }).summary['Pendientes'],
        'No disponible',
      );
    },
  );

  test(
    'La actividad usa el cierre para su estado y conserva la fecha planificada',
    () {
      final pending = FieldRecordInfo.actividad(activity);
      expect(pending.status, 'Pendiente');
      expect(pending.summary['Lote'], 'Parcela Los Pinos');
      expect(pending.summary['Fecha planificada'], '29/10/2026');
      expect(pending.details['Cultivo'], 'Maíz');
      expect(pending.details['Responsable'], 'Carmen Lima');
      expect(
        FieldRecordInfo.actividad({
          ...activity,
          'fechafin': '2026-10-28T15:00:00Z',
        }).status,
        'Completada',
      );
      expect(FieldRecordInfo.actividad({'actividadid': 11}).status, isNull);
      expect(
        FieldRecordInfo.actividad({...activity, 'fechafin': ''}).status,
        isNull,
      );
    },
  );

  test(
    'Los nombres que la API no entrega no se sustituyen por datos inventados',
    () {
      final hidden = FieldRecordInfo.actividad({
        'actividadid': 11,
        'loteid': 7,
        'usuarioid': 99,
        'fechafin': null,
      });
      expect(hidden.summary['Lote'], '#7');
      expect(hidden.summary['Responsable'], 'No disponible');
      expect(hidden.details['Cultivo'], 'No disponible');
      expect(hidden.details['Tipo de actividad'], 'No disponible');
      expect(hidden.details['Fecha planificada'], 'Sin registrar');
      expect(hidden.details.values, isNot(contains('99')));
    },
  );

  test('Rechaza relaciones, fechas y cantidades incoherentes', () {
    for (final invalid in [
      {...lot, 'insumo_semilla': null, 'cultivo': []},
      {
        ...lot,
        'usuario': {'nombre': {}},
      },
      {...lot, 'fechasiembra': '2026-02-30'},
      {...lot, 'fechasiembra': 'sin fecha'},
      {...lot, 'superficie': -1},
      {...lot, 'actividades_pendientes': -1},
      {...lot, 'actividades_pendientes': 2.5},
      {...lot, 'actividades': 'sin datos'},
      {
        ...lot,
        'actividades': [
          {'fechafin': true},
        ],
      },
    ]) {
      expect(() => FieldRecordInfo.lote(invalid), throwsA(isA<ApiException>()));
    }
  });

  group('Presentación en Flutter', () {
    const storage = SessionStorage();
    const profile = {
      'usuarioid': 1,
      'nombre': 'Ana',
      'email': 'ana@example.test',
      'activo': true,
      'estado_cuenta': 'aprobado',
      'permissions': ['lotes.view'],
    };
    http.Response json(Object? value) => http.Response(
      jsonEncode(value),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    Future<void> start(
      WidgetTester tester,
      Future<http.Response> Function(http.Request) handler,
    ) async {
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient(handler),
      );
      addTearDown(api.close);
      await tester.pumpWidget(AgroFusionApp(apiClient: api));
      await tester.pumpAndSettle();
    }

    Future<void> push(WidgetTester tester, AppModule module) async {
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .pushNamed(module.route),
      );
      await tester.pumpAndSettle();
    }

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      await storage.saveToken('1|informacion');
    });

    testWidgets(
      'El cultivo y el responsable se leen y se buscan desde la lista',
      (tester) async {
        var listCalls = 0;
        await start(tester, (request) async {
          if (request.url.path == '/api/me') return json(profile);
          if (request.url.path == '/api/lotes') {
            listCalls++;
            return json([lot]);
          }
          return json({
            ...lot,
            'actividades': [
              activity,
              {...activity, 'fechafin': '2026-10-28T12:00:00Z'},
            ],
          });
        });
        await push(tester, AppModule.lotes);
        expect(find.text('Cultivo: Maíz amarillo'), findsOneWidget);
        expect(find.text('Responsable: Carmen Lima'), findsOneWidget);
        expect(find.text('Siembra: 20/10/2026'), findsOneWidget);
        expect(find.text('Pendientes: No disponible'), findsOneWidget);
        expect(find.text('Sembrado'), findsOneWidget);
        await tester.tap(find.byTooltip('Buscar lotes'));
        await tester.pumpAndSettle();
        for (final query in [
          'AMARILLO',
          'carmen lima',
          'sembrado',
          '20/10/2026',
        ]) {
          await tester.enterText(find.byType(TextField), query);
          await tester.pumpAndSettle();
          expect(find.text('Parcela Los Pinos'), findsOneWidget);
        }
        expect(listCalls, 1);
        await tester.tap(find.text('Parcela Los Pinos'));
        await tester.pumpAndSettle();
        expect(find.text('Carmen Lima'), findsOneWidget);
        expect(find.text('1.000,20 hectáreas'), findsOneWidget);
        await tester.ensureVisible(find.text('Actividades pendientes'));
        await tester.pumpAndSettle();
        expect(find.text('1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Las actividades distinguen pendientes y completadas en las tarjetas',
      (tester) async {
        await start(tester, (request) async {
          if (request.url.path == '/api/me') return json(profile);
          if (request.url.path == '/api/actividades') {
            return json([
              activity,
              {
                ...activity,
                'actividadid': 12,
                'descripcion': 'Siembra terminada',
                'fechafin': '2026-10-28T15:00:00Z',
              },
            ]);
          }
          return json(activity);
        });
        await push(tester, AppModule.actividades);
        expect(find.text('Pendiente'), findsOneWidget);
        await tester.tap(find.byTooltip('Buscar actividades'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'completada');
        await tester.pumpAndSettle();
        expect(find.text('Siembra terminada'), findsOneWidget);
        expect(find.text('Riego de Los Pinos'), findsNothing);
        await tester.enterText(find.byType(TextField), 'pendiente carmen');
        await tester.pumpAndSettle();
        expect(find.text('Riego de Los Pinos'), findsOneWidget);
        await tester.tap(find.text('Riego de Los Pinos'));
        await tester.pumpAndSettle();
        expect(find.text('29/10/2026'), findsOneWidget);
        await tester.ensureVisible(
          find.text('Revisar los surcos del sector norte.'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Revisar los surcos del sector norte.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Los datos ocultos de la API actual se muestran como no disponibles',
      (tester) async {
        await start(
          tester,
          (request) async => json(
            request.url.path == '/api/me'
                ? profile
                : [
                    {
                      'actividadid': 11,
                      'descripcion': 'Riego',
                      'loteid': 7,
                      'usuarioid': 99,
                      'fechafin': null,
                    },
                  ],
          ),
        );
        await push(tester, AppModule.actividades);
        expect(find.text('Lote: #7'), findsOneWidget);
        expect(find.text('Responsable: No disponible'), findsOneWidget);
        expect(find.text('Pendiente'), findsOneWidget);
        expect(find.text('Responsable: Ana'), findsNothing);
      },
    );
  });
}
