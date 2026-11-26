import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/widgets/today_tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'token'});

  const user = AuthUser(
    id: 1,
    name: 'Ana',
    email: 'ana@example.test',
    roles: ['agricultor'],
    permissions: {'lotes.view'},
  );

  Future<void> pump(WidgetTester tester, List<Object> rows) async {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'http://localhost/api'),
      sessionStorage: const SessionStorage(),
      client: MockClient((_) async => http.Response(jsonEncode(rows), 200)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayTasks(
            user: user,
            service: ModuleService(api),
            onOpen: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Cuenta y lista las actividades pendientes', (tester) async {
    await pump(tester, [
      {'actividadid': 1, 'descripcion': 'Regar el lote Norte'},
      {'actividadid': 2, 'descripcion': 'Fumigar el lote Sur'},
    ]);
    expect(find.text('Te tocan 2 actividades'), findsOneWidget);
    expect(find.text('Regar el lote Norte'), findsOneWidget);
  });

  testWidgets('Sin actividades no ocupa lugar', (tester) async {
    await pump(tester, []);
    expect(find.textContaining('Te toca'), findsNothing);
  });
}
