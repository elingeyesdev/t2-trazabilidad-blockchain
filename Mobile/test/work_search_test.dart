import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/screens/home/home_screen.dart';
import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Busca herramientas autorizadas y permite limpiar la búsqueda', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          user: const AuthUser(
            id: 1,
            name: 'Ana',
            email: 'ana@example.test',
            permissions: {'lotes.view', 'inventario.view'},
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lotes');
    await tester.pumpAndSettle();
    expect(find.text('Lotes'), findsOneWidget);
    expect(find.text('Almacenes'), findsNothing);
    expect(find.text('Usuarios'), findsNothing);

    await tester.enterText(find.byType(TextField), 'usuarios');
    await tester.pumpAndSettle();
    expect(find.text('No encontramos herramientas'), findsOneWidget);
    expect(find.text('Usuarios'), findsNothing);

    await tester.tap(find.byTooltip('Limpiar herramientas'));
    await tester.pumpAndSettle();
    expect(find.text('Lotes'), findsOneWidget);
    expect(find.text('Almacenes'), findsOneWidget);
    expect(find.text('Usuarios'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'insumos');
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'insumos',
    );
    expect(find.text('Lotes'), findsNothing);
    expect(find.text('Insumos'), findsOneWidget);
  });
}
