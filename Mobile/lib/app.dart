import 'package:flutter/material.dart';

import 'config/api_config.dart';
import 'controllers/auth_controller.dart';
import 'navigation/app_routes.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/connection/connection_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/api_client.dart';
import 'services/api_health_service.dart';
import 'services/auth_service.dart';
import 'services/session_storage.dart';

class AgroFusionApp extends StatefulWidget {
  const AgroFusionApp({
    super.key,
    this.apiClient,
    this.sessionStorage = const SessionStorage(),
  });

  final ApiClient? apiClient;
  final SessionStorage sessionStorage;

  @override
  State<AgroFusionApp> createState() => _AgroFusionAppState();
}

class _AgroFusionAppState extends State<AgroFusionApp> {
  late final ApiClient _api =
      widget.apiClient ??
      ApiClient(
        config: ApiConfig.fromEnvironment(),
        sessionStorage: widget.sessionStorage,
      );
  late final AuthController _auth = AuthController(
    AuthService(_api, widget.sessionStorage),
  );

  @override
  void dispose() {
    _auth.dispose();
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
        AppRoutes.home: (_) => ListenableBuilder(
          listenable: _auth,
          builder: (context, _) {
            final user = _auth.user;
            return user == null
                ? LoginScreen(controller: _auth)
                : HomeScreen(user: user);
          },
        ),
        AppRoutes.connection: (_) =>
            ConnectionScreen(healthService: ApiHealthService(_api)),
        AppRoutes.register: (_) => RegisterScreen(controller: _auth),
      },
    );
  }
}
