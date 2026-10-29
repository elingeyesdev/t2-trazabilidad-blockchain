import 'package:flutter/material.dart';

import '../../navigation/app_routes.dart';
import '../../widgets/app_empty_state.dart';

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
      child: AppEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Acceso no autorizado',
        message: 'No tienes permiso para consultar este módulo.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
  );
}
