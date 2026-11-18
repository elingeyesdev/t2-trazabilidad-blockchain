import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/api_health.dart';
import '../../services/api_health_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.healthService});

  final ApiHealthService healthService;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late Future<ApiHealth> _health;

  @override
  void initState() {
    super.initState();
    _health = widget.healthService.check();
  }

  void _retry() {
    setState(() {
      _health = widget.healthService.check();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estado de conexión')),
      body: SafeArea(
        child: FutureBuilder<ApiHealth>(
          future: _health,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoading(message: 'Comprobando conexión...');
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              return AppErrorState(
                message: error is ApiException
                    ? error.message
                    : 'No se pudo comprobar la conexión. Intenta de nuevo.',
                onRetry: _retry,
              );
            }

            return Semantics(
              liveRegion: true,
              child: AppEmptyState(
                icon: Icons.wifi_rounded,
                tone: AppTheme.sprout,
                ink: AppTheme.fieldDeep,
                title: 'Conexión disponible',
                message: 'El servicio de AgroFusion está disponible.',
                action: OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Volver a comprobar'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
