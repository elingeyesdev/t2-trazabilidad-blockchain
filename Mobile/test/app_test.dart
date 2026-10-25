import 'package:agrofusion_mobile/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('El punto de entrada muestra la pantalla inicial sin errores', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('AgroFusion'), findsOneWidget);
    expect(find.text('Trazabilidad agrícola'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
