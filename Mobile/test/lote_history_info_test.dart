import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/screens/modules/lote_activity_history_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:agrofusion_mobile/widgets/activity_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const user = AuthUser(
    id: 1,
    name: 'Ana',
    email: 'ana@example.test',
    permissions: {'lotes.view'},
  );
  const pending = {
    'actividadid': 71,
    'loteid': 7,
    'descripcion': 'Riego del sector norte',
    'fechainicio': '2026-11-01',
    'fechafin': null,
    'usuario': {'usuarioid': 2, 'nombre': 'Carmen', 'apellido': 'Lima'},
    'observaciones': 'Comprobar la humedad antes de regar.',
  };

  Future<void> start(WidgetTester tester, List<Object?> rows) async {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: const SessionStorage(),
      client: MockClient((request) async {
        expect(request.url.path, '/api/lotes/7/actividades');
        return http.Response(
          jsonEncode({
            'data': rows,
            'meta': {'current_page': 1, 'last_page': 1},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
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

  Finder cardText(String title, String text) => find.descendant(
    of: find.widgetWithText(ActivityHistoryCard, title),
    matching: find.text(text),
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Cada tarjeta conserva fecha, responsable, estado y observaciones de su actividad',
    (tester) async {
      await start(tester, [
        pending,
        {
          ...pending,
          'actividadid': 72,
          'descripcion': 'Preparación del terreno',
          'fechainicio': '2026-10-30',
          'fechafin': '2026-10-31',
          'usuario': {'usuarioid': 3, 'nombre': 'Luis', 'apellido': 'Soto'},
          'ejecutor': {'usuarioid': 4, 'nombre': 'Pedro', 'apellido': 'Rojas'},
          'observaciones': 'Surcos terminados en el sector alto.',
        },
      ]);
      const first = 'Riego del sector norte';
      expect(cardText(first, 'Inicio: 01/11/2026'), findsOneWidget);
      expect(cardText(first, 'Pendiente'), findsOneWidget);
      expect(cardText(first, 'Carmen Lima'), findsOneWidget);
      expect(
        cardText(first, 'Comprobar la humedad antes de regar.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Preparación del terreno'),
        200,
      );
      const second = 'Preparación del terreno';
      expect(cardText(second, 'Inicio: 30/10/2026'), findsOneWidget);
      expect(cardText(second, 'Finalización: 31/10/2026'), findsOneWidget);
      expect(cardText(second, 'Completada'), findsOneWidget);
      expect(cardText(second, 'Luis Soto'), findsOneWidget);
      expect(
        cardText(second, 'Surcos terminados en el sector alto.'),
        findsOneWidget,
      );
      expect(cardText(second, 'Carmen Lima'), findsNothing);
      expect(find.text('Pedro Rojas'), findsNothing);
    },
  );

  testWidgets(
    'Distingue información ausente de una actividad sin observaciones',
    (tester) async {
      await start(tester, [
        {...pending, 'usuario': null, 'observaciones': null},
        {
          'actividadid': 73,
          'loteid': 7,
          'descripcion': 'Actividad sin datos completos',
        },
      ]);
      const first = 'Riego del sector norte';
      expect(cardText(first, 'No disponible'), findsOneWidget);
      expect(cardText(first, 'Sin observaciones'), findsOneWidget);
      expect(cardText(first, 'Pendiente'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Actividad sin datos completos'),
        200,
      );
      const second = 'Actividad sin datos completos';
      expect(cardText(second, 'Estado no disponible'), findsOneWidget);
      expect(cardText(second, 'Inicio: Sin registrar'), findsOneWidget);
      expect(cardText(second, 'No disponible'), findsNWidgets(2));
      expect(cardText(second, 'Pendiente'), findsNothing);
      expect(cardText(second, 'Sin observaciones'), findsNothing);
    },
  );

  for (final size in [const Size(320, 740), const Size(812, 375)]) {
    testWidgets(
      'Muestra completos los nombres y notas con letras grandes en $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const responsible = 'María Fernanda de los Ángeles Fernández';
        final observations = List.filled(
          6,
          'Revisar los surcos y cerrar las válvulas antes de salir del lote.',
        ).join(' ');
        await start(tester, [
          {
            ...pending,
            'usuario': {'nombre': responsible},
            'observaciones': observations,
          },
        ]);
        await tester.scrollUntilVisible(
          find.text(responsible),
          250,
          maxScrolls: 50,
        );
        await tester.ensureVisible(find.text(observations));
        expect(find.text(observations), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
