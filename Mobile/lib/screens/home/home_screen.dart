import 'package:flutter/material.dart';

import '../../models/auth_user.dart';
import '../../navigation/app_routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AgroFusion')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.eco_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Hola, ${user.name}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(user.email, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Text(
                  'Trazabilidad agrícola',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.connection);
                  },
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Comprobar conexión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
