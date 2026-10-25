import 'package:flutter/material.dart';

import 'config/api_config.dart';
import 'navigation/app_routes.dart';
import 'screens/connection/connection_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/api_client.dart';
import 'services/api_health_service.dart';
import 'services/session_storage.dart';

class AgroFusionApp extends StatefulWidget {
  const AgroFusionApp({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<AgroFusionApp> createState() => _AgroFusionAppState();
}

class _AgroFusionAppState extends State<AgroFusionApp> {
  late final ApiClient _api =
      widget.apiClient ??
      ApiClient(
        config: ApiConfig.fromEnvironment(),
        sessionStorage: const SessionStorage(),
      );

  @override
  void dispose() {
    if (widget.apiClient == null) {
      _api.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroFusion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
      ),
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (_) => const HomeScreen(),
        AppRoutes.connection: (_) =>
            ConnectionScreen(healthService: ApiHealthService(_api)),
      },
    );
  }
}
