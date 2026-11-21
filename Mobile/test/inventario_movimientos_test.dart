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

  const gestorProfile = {
    'usuarioid': 12,
    'nombre': 'Carlos',
    'apellido': 'Mendoza',
    'email': 'carlos@example.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 2, 'name': 'jefe_agricultor'},
    ],
    'permissions': [
      'inventario.view',
      'almacen.movimientos.view',
      'almacen.ingresos.create',
      'almacen.salidas.create',
    ],
  };

  const almacenesPayload = [
    {
      'almacenid': 4,
      'nombre': 'Almacén Agrícola Norte',
      'ubicacion': 'Sector A',
      'capacidad': 5000,
      'ambito': 'agricola',
      'activo': true,
    },
  ];

  Map<String, dynamic> buildExistencia(double stock) => {
    'insumoid': 101,
    'nombre': 'Fertilizante NPK',
    'unidadmedidaid': 1,
    'unidad': 'kg',
    'cantidad_fisica': stock.toStringAsFixed(6),
    'cantidad_disponible': stock.toStringAsFixed(6),
    'cantidad_vencida': '0.000000',
    'cantidad_bloqueada': '0.000000',
    'cantidad_reservada': '0.000000',
    'cantidad_sin_partida': stock.toStringAsFixed(6),
    'minimo': '10.000000',
    'existencias_bajas': stock <= 10,
    'partidas': <Map<String, Object?>>[],
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
    await storage.saveToken('1|inventario-test');
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(AgroFusionApp(apiClient: api));
    await tester.pumpAndSettle();
  }

  Future<void> openAlmacenDetail(WidgetTester tester) async {
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Almacenes'));
    await tester.tap(find.text('Almacenes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Almacén Agrícola Norte'));
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Consulta almacén y existencias, registra entrada y salida validando stock insuficiente y actualiza historial',
    (tester) async {
      var stock = 20.0;
      final movimientos = <Map<String, dynamic>>[];
      Map<String, dynamic>? lastIngresoBody;
      var salidaCalls = 0;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(gestorProfile);
        if (request.url.path == '/api/almacenes' && request.method == 'GET') {
          return jsonResponse(almacenesPayload);
        }
        if (request.url.path == '/api/almacenes/4/existencias' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [buildExistencia(stock)],
            'current_page': 1,
            'last_page': 1,
          });
        }
        if (request.url.path == '/api/almacenes/4/movimientos' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': movimientos,
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/almacen-movimientos/ingreso' &&
            request.method == 'POST') {
          lastIngresoBody = jsonDecode(request.body) as Map<String, dynamic>;
          final qty = double.parse(lastIngresoBody!['cantidad'].toString());
          final prev = stock;
          stock += qty;
          final created = {
            'almacen_movimientoid': 301,
            'almacenid': 4,
            'insumoid': 101,
            'tipo_movimiento_almacenid': 1,
            'fecha': lastIngresoBody!['fecha'],
            'cantidad': qty,
            'cantidad_decimal': qty.toStringAsFixed(6),
            'unidad': 'kg',
            'saldo_anterior': prev.toStringAsFixed(6),
            'saldo_posterior': stock.toStringAsFixed(6),
            'insumo': {'insumoid': 101, 'nombre': 'Fertilizante NPK'},
            'tipo': {'nombre': 'Compra', 'naturaleza': 'ingreso'},
            'usuario': {
              'usuarioid': 12,
              'nombre': 'Carlos',
              'apellido': 'Mendoza',
            },
          };
          movimientos.insert(0, created);
          return jsonResponse(created, 201);
        }
        if (request.url.path == '/api/almacen-movimientos/salida' &&
            request.method == 'POST') {
          salidaCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final qty = double.parse(body['cantidad'].toString());
          final prev = stock;
          stock -= qty;
          final created = {
            'almacen_movimientoid': 302,
            'almacenid': 4,
            'insumoid': 101,
            'tipo_movimiento_almacenid': 5,
            'fecha': body['fecha'],
            'cantidad': qty,
            'cantidad_decimal': qty.toStringAsFixed(6),
            'unidad': 'kg',
            'saldo_anterior': prev.toStringAsFixed(6),
            'saldo_posterior': stock.toStringAsFixed(6),
            'insumo': {'insumoid': 101, 'nombre': 'Fertilizante NPK'},
            'tipo': {'nombre': 'Envío', 'naturaleza': 'salida'},
            'usuario': {
              'usuarioid': 12,
              'nombre': 'Carlos',
              'apellido': 'Mendoza',
            },
          };
          movimientos.insert(0, created);
          return jsonResponse(created, 201);
        }
        return jsonResponse({}, 404);
      });

      await openAlmacenDetail(tester);

      expect(find.text('Existencias autorizadas'), findsOneWidget);
      expect(find.text('Fertilizante NPK'), findsOneWidget);
      expect(find.text('20 kg'), findsAtLeastNWidgets(1));

      // 1. Registra entrada de 5.5 kg.
      await tester.tap(find.byKey(const ValueKey('almacen.registrar_entrada')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('movimiento.cantidad')),
        '5.5',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Registrar entrada'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar entrada'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar movimiento'),
      );
      await tester.pumpAndSettle();

      expect(lastIngresoBody, isNotNull);
      expect(lastIngresoBody!['almacenid'], 4);
      expect(lastIngresoBody!['insumoid'], 101);
      expect(lastIngresoBody!['cantidad'], '5.5');
      expect(lastIngresoBody!.containsKey('unidadmedidaid'), isFalse);
      expect(lastIngresoBody!.containsKey('stock'), isFalse);

      expect(find.text('25.5 kg'), findsAtLeastNWidgets(1));
      expect(find.text('Compra · Fertilizante NPK'), findsOneWidget);
      expect(find.text('+5.5 kg'), findsOneWidget);

      // 2. Intenta salida mayor al disponible (40 kg > 25.5 kg) -> bloquea y avisa.
      await tester.tap(find.byKey(const ValueKey('almacen.registrar_salida')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('movimiento.cantidad')),
        '40',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No hay cantidad suficiente: disponible 25.5 kg'),
        findsAtLeastNWidgets(1),
      );

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Registrar salida'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar salida'));
      await tester.pumpAndSettle();
      expect(salidaCalls, 0);

      // Corrige salida a 10 kg -> confirma y actualiza disponible a 15.5 kg.
      await tester.ensureVisible(
        find.byKey(const ValueKey('movimiento.cantidad')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('movimiento.cantidad')),
        '10',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Registrar salida'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar salida'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar movimiento'),
      );
      await tester.pumpAndSettle();

      expect(salidaCalls, 1);
      expect(find.text('15.5 kg'), findsAtLeastNWidgets(1));
      expect(find.text('Envío · Fertilizante NPK'), findsOneWidget);
      expect(find.text('-10 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'Los ajustes exigen motivo obligatorio y muestran el resultado y saldo actualizado',
    (tester) async {
      var stock = 18.0;
      final movimientos = <Map<String, dynamic>>[];
      var ajusteCalls = 0;

      await startApp(tester, (request) async {
        if (request.url.path == '/api/me') return jsonResponse(gestorProfile);
        if (request.url.path == '/api/almacenes' && request.method == 'GET') {
          return jsonResponse(almacenesPayload);
        }
        if (request.url.path == '/api/almacenes/4/existencias' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': [buildExistencia(stock)],
            'current_page': 1,
            'last_page': 1,
          });
        }
        if (request.url.path == '/api/almacenes/4/movimientos' &&
            request.method == 'GET') {
          return jsonResponse({
            'data': movimientos,
            'meta': {'current_page': 1, 'last_page': 1},
          });
        }
        if (request.url.path == '/api/almacen-movimientos/ingreso' &&
            request.method == 'POST') {
          ajusteCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final qty = double.parse(body['cantidad'].toString());
          final prev = stock;
          stock += qty;
          final created = {
            'almacen_movimientoid': 303,
            'almacenid': 4,
            'insumoid': 101,
            'tipo_movimiento_almacenid': 4,
            'fecha': body['fecha'],
            'cantidad': qty,
            'cantidad_decimal': qty.toStringAsFixed(6),
            'unidad': 'kg',
            'destino_motivo': body['destino_motivo'],
            'saldo_anterior': prev.toStringAsFixed(6),
            'saldo_posterior': stock.toStringAsFixed(6),
            'insumo': {'insumoid': 101, 'nombre': 'Fertilizante NPK'},
            'tipo': {'nombre': 'Ajuste positivo', 'naturaleza': 'ingreso'},
            'usuario': {
              'usuarioid': 12,
              'nombre': 'Carlos',
              'apellido': 'Mendoza',
            },
          };
          movimientos.insert(0, created);
          return jsonResponse(created, 201);
        }
        return jsonResponse({}, 404);
      });

      await openAlmacenDetail(tester);

      await tester.tap(find.byKey(const ValueKey('almacen.registrar_ajuste')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('movimiento.cantidad')),
        '2',
      );

      // Sin motivo -> bloquea y exige motivo obligatorio.
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Registrar ajuste'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar ajuste'));
      await tester.pumpAndSettle();

      expect(ajusteCalls, 0);
      expect(
        find.text('Describe el motivo obligatorio del ajuste.'),
        findsOneWidget,
      );

      // Con motivo -> confirma y muestra resultado + saldo actualizado.
      await tester.ensureVisible(
        find.byKey(const ValueKey('movimiento.motivo')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('movimiento.motivo')),
        'Conteo físico mensual en bodega',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Registrar ajuste'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar ajuste'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar movimiento'),
      );
      await tester.pumpAndSettle();

      expect(ajusteCalls, 1);
      expect(
        find.textContaining('Ajuste positivo registrado (+2 kg'),
        findsOneWidget,
      );
      expect(find.text('20 kg'), findsAtLeastNWidgets(1));
      expect(
        find.text('Motivo: Conteo físico mensual en bodega'),
        findsOneWidget,
      );
    },
  );
}
