import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/screens/modules/lote_activity_history_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();
  const user = AuthUser(
    id: 1,
    name: 'Ana',
    email: 'ana@example.test',
    permissions: {'lotes.view'},
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
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoteActivityHistoryScreen(
          loteId: 7,
          loteName: 'Parcela Norte',
          user: user,
          service: ModuleService(api),
          onRefreshPermissions: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  http.Response page(List<Object?> rows, {int number = 1, int last = 1}) =>
      http.Response(
        jsonEncode({
          'data': rows,
          'meta': {'current_page': number, 'last_page': last},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|historial-fechas');
  });

  testWidgets(
    'Solicita el orden por inicio en todas las páginas y al actualizar',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = <int>[];
      await start(tester, (request) async {
        expect(request.url.path, '/api/lotes/7/actividades');
        expect(request.url.queryParameters['sort'], 'fechainicio');
        expect(request.url.queryParameters['direction'], 'desc');
        final number = int.parse(request.url.queryParameters['page']!);
        pages.add(number);
        return page(
          number == 1
              ? [
                  {
                    'actividadid': 2,
                    'loteid': 7,
                    'descripcion': 'Riego reciente',
                    'fechainicio': '2026-10-31',
                    'fecha_planificada': '2026-11-10',
                  },
                  {
                    'actividadid': 80,
                    'loteid': 7,
                    'descripcion': 'Preparación del terreno',
                    'fechainicio': '2026-10-01',
                  },
                ]
              : [
                  {
                    'actividadid': 150,
                    'loteid': 7,
                    'descripcion': 'Trabajo del año anterior',
                    'fechainicio': '2025-12-31',
                  },
                ],
          number: number,
          last: 2,
        );
      });
      expect(
        find.text('Más recientes primero, según su fecha de inicio.'),
        findsOneWidget,
      );
      expect(find.text('Inicio: 31/10/2026'), findsOneWidget);
      expect(find.text('Inicio: 01/10/2026'), findsOneWidget);
      expect(find.textContaining('10/11/2026'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Riego reciente')).dy,
        lessThan(tester.getTopLeft(find.text('Preparación del terreno')).dy),
      );
      await tester.scrollUntilVisible(find.text('Siguiente'), 200);
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Inicio: 31/12/2025'), findsOneWidget);
      expect(find.text('Riego reciente'), findsNothing);
      await tester.tap(find.byTooltip('Actualizar historial'));
      await tester.pumpAndSettle();
      expect(find.text('Inicio: 31/12/2025'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Anterior'), 200);
      await tester.tap(find.text('Anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Inicio: 31/10/2026'), findsOneWidget);
      expect(pages, [1, 2, 2, 1]);
    },
  );

  testWidgets(
    'Una fecha de inicio ausente se informa sin inventar otra fecha',
    (tester) async {
      await start(
        tester,
        (_) async => page([
          {
            'actividadid': 7,
            'loteid': 7,
            'descripcion': 'Actividad por iniciar',
            'fecha_planificada': '2026-11-05',
            'fechainicio': null,
          },
        ]),
      );
      expect(find.text('Inicio: Sin registrar'), findsOneWidget);
      expect(find.textContaining('05/11/2026'), findsNothing);
    },
  );
}
