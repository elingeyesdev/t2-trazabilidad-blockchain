import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:agrofusion_mobile/widgets/form_validation.dart';
import 'package:agrofusion_mobile/widgets/location_input_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpLocationForm(
    WidgetTester tester, {
    required GlobalKey<FormState> formKey,
    required TextEditingController location,
    TextEditingController? latitude,
    TextEditingController? longitude,
    Future<DeviceLocation?> Function()? requestLocation,
    ValueChanged<DeviceLocation?>? onCoordinatesChanged,
    bool requiredField = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LocationInputField(
                    controller: location,
                    latitudeController: latitude,
                    longitudeController: longitude,
                    requestLocation: requestLocation,
                    onCoordinatesChanged: onCoordinatesChanged,
                    requiredField: requiredField,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => validateForm(formKey),
                    child: const Text('Guardar ubicación'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Explica la denegación de ubicación y permite introducirla manualmente',
    (tester) async {
      final formKey = GlobalKey<FormState>();
      final location = TextEditingController();
      final latitude = TextEditingController();
      final longitude = TextEditingController();
      DeviceLocation? savedCoords;
      addTearDown(location.dispose);
      addTearDown(latitude.dispose);
      addTearDown(longitude.dispose);

      await pumpLocationForm(
        tester,
        formKey: formKey,
        location: location,
        latitude: latitude,
        longitude: longitude,
        onCoordinatesChanged: (coords) => savedCoords = coords,
        requestLocation: () async => throw PlatformException(
          code: 'location_permission_denied',
          message: 'Permiso denegado',
        ),
      );

      await tester.tap(find.text('Usar ubicación actual'));
      await tester.pumpAndSettle();

      expect(find.text('Permiso de ubicación denegado'), findsOneWidget);
      expect(
        find.textContaining(
          'El teléfono no permitió obtener la ubicación actual.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('location.latitud')), findsOneWidget);
      expect(find.byKey(const ValueKey('location.longitud')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('location.ubicacion')),
        'Sector Norte, Parcela Los Pinos',
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.latitud')),
        '-17.7833',
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.longitud')),
        '-63.1821',
      );
      await tester.pumpAndSettle();

      expect(validateForm(formKey), isTrue);
      expect(location.text, 'Sector Norte, Parcela Los Pinos');
      expect(savedCoords?.latitude, closeTo(-17.7833, 0.0001));
      expect(savedCoords?.longitude, closeTo(-63.1821, 0.0001));
      expect(
        find.text('Coordenadas registradas: -17.7833, -63.1821'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Registra la ubicación del dispositivo cuando el permiso está concedido y permite ajustarla',
    (tester) async {
      final formKey = GlobalKey<FormState>();
      final location = TextEditingController();
      DeviceLocation? savedCoords;
      addTearDown(location.dispose);

      await pumpLocationForm(
        tester,
        formKey: formKey,
        location: location,
        onCoordinatesChanged: (coords) => savedCoords = coords,
        requestLocation: () async => const DeviceLocation(
          latitude: -17.7516,
          longitude: -63.2367,
          address: 'Urubó, Municipio Porongo',
        ),
      );

      await tester.tap(find.text('Usar ubicación actual'));
      await tester.pumpAndSettle();

      expect(find.text('Permiso de ubicación denegado'), findsNothing);
      expect(location.text, 'Urubó, Municipio Porongo');
      expect(
        find.text('Coordenadas registradas: -17.7516, -63.2367'),
        findsOneWidget,
      );
      expect(savedCoords?.latitude, -17.7516);
      expect(savedCoords?.longitude, -63.2367);

      await tester.enterText(
        find.byKey(const ValueKey('location.ubicacion')),
        'Urubó, Parcela 2',
      );
      await tester.pumpAndSettle();
      expect(validateForm(formKey), isTrue);
      expect(location.text, 'Urubó, Parcela 2');
    },
  );

  testWidgets(
    'Valida qué dato de ubicación o coordenada debe completarse o corregirse',
    (tester) async {
      final formKey = GlobalKey<FormState>();
      final location = TextEditingController();
      addTearDown(location.dispose);

      await pumpLocationForm(tester, formKey: formKey, location: location);

      await tester.tap(find.text('Guardar ubicación'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ingresa la ubicación o regístrala con el dispositivo.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Introducir coordenadas manualmente'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('location.ubicacion')),
        'Parcela Central',
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.latitud')),
        '99',
      );
      await tester.enterText(
        find.byKey(const ValueKey('location.longitud')),
        '-195',
      );
      await tester.tap(find.text('Guardar ubicación'));
      await tester.pumpAndSettle();

      expect(find.text('Ingresa una latitud entre -90 y 90.'), findsOneWidget);
      expect(
        find.text('Ingresa una longitud entre -180 y 180.'),
        findsOneWidget,
      );
    },
  );
}
