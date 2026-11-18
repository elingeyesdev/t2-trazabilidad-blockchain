import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Carga con un anillo claro y mensaje en texto grande.
/// Es sin animación repetida infinita para que las pruebas (`pumpAndSettle`)
/// y los teléfonos de gama baja no queden ocupados.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.message = 'Cargando...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox.expand(
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        strokeCap: StrokeCap.round,
                        color: AppTheme.field,
                        backgroundColor: AppTheme.sprout,
                      ),
                    ),
                    const Icon(
                      Icons.eco_rounded,
                      color: AppTheme.field,
                      size: 32,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
