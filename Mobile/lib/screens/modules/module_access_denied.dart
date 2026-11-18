import 'package:flutter/material.dart';

import '../../navigation/app_routes.dart';
import '../../theme/app_theme.dart';
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
        tone: AppTheme.maizeSoft,
        ink: const Color(0xFF5F4100),
        title: 'Acceso no autorizado',
        message: 'No tienes permiso para consultar este módulo.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: onRefreshPermissions,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar permisos'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    ),
  );
}
