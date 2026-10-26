import 'package:agrofusion_mobile/main.dart' as app;
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('El punto de entrada solicita iniciar sesión sin errores', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('AgroFusion'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
