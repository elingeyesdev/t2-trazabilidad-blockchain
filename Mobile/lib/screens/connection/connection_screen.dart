import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/api_health.dart';
import '../../services/api_health_service.dart';
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

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Conexión disponible',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'El servicio de AgroFusion está disponible.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
