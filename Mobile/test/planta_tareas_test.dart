import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
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
}
