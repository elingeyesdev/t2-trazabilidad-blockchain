import 'package:flutter/material.dart';

import '../../navigation/app_routes.dart';

class ModuleAccessDenied extends StatelessWidget {
  const ModuleAccessDenied({
    super.key,
    required this.title,
    required this.onRefreshPermissions,
  });

  final String title;
  final VoidCallback onRefreshPermissions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                'Acceso no autorizado',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'No tienes permiso para consultar este módulo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRefreshPermissions,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar permisos'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
