import 'dart:async';

import 'package:flutter/material.dart';

import 'config/api_config.dart';
import 'controllers/auth_controller.dart';
import 'navigation/app_module.dart';
import 'navigation/app_routes.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/connection/connection_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/modules/module_access_denied.dart';
import 'screens/modules/module_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'services/api_client.dart';
import 'services/api_health_service.dart';
import 'services/auth_service.dart';
import 'services/module_service.dart';
import 'services/session_storage.dart';
import 'widgets/app_error_state.dart';
import 'widgets/app_loading.dart';

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

class _AgroFusionAppState extends State<AgroFusionApp>
    with WidgetsBindingObserver {
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_auth.restoreSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _auth.user != null) {
      unawaited(_auth.restoreSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.dispose();
    if (widget.apiClient == null) {
      _api.close();
    }
    super.dispose();
  }

  Widget _sessionGate(
    Widget Function() content, {
    bool requiresAuthentication = false,
    AppModule? module,
  }) {
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) {
        if (_auth.isCheckingSession || _auth.isLoggingOut) {
          return PopScope(
            canPop: false,
            child: Scaffold(
              body: AppLoading(
                message: _auth.isCheckingSession
                    ? 'Verificando sesión...'
                    : 'Cerrando sesión...',
              ),
            ),
          );
        }
        final logout = _auth.logoutResult;
        if (logout != null && !logout.localCleared) {
          return PopScope(
            canPop: false,
            child: Scaffold(
              body: AppErrorState(
                message: logout.message,
                onRetry: _auth.logout,
              ),
            ),
          );
        }
        final error = _auth.sessionError;
        if (error != null) {
          return PopScope(
            canPop: false,
            child: Scaffold(
              appBar: AppBar(title: const Text('AgroFusion')),
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: AppErrorState(
                        message: error.message,
                        onRetry: _auth.restoreSession,
                      ),
                    ),
                    TextButton(
                      onPressed: _auth.logout,
                      child: const Text('Cerrar sesión'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        }
        if ((requiresAuthentication || module != null) && _auth.user == null) {
          return LoginScreen(controller: _auth);
        }
        if (module != null && !module.canOpen(_auth.user!)) {
          return ModuleAccessDenied(
            title: module.label,
            onRefreshPermissions: _auth.restoreSession,
          );
        }
        return content();
      },
    );
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
        AppRoutes.home: (_) => _sessionGate(
          () => HomeScreen(user: _auth.user!, onLogout: _auth.logout),
          requiresAuthentication: true,
        ),
        AppRoutes.connection: (_) => _sessionGate(
          () => ConnectionScreen(healthService: ApiHealthService(_api)),
        ),
        AppRoutes.register: (_) =>
            _sessionGate(() => RegisterScreen(controller: _auth)),
        AppRoutes.profile: (_) => _sessionGate(
          () => ProfileScreen(controller: _auth),
          requiresAuthentication: true,
        ),
        for (final module in AppModule.values)
          module.route: (_) => _sessionGate(
            () => ModuleScreen(
              key: ValueKey(_auth.user),
              module: module,
              user: _auth.user!,
              service: ModuleService(_api),
              onRefreshPermissions: _auth.restoreSession,
            ),
            requiresAuthentication: true,
            module: module,
          ),
      },
    );
  }
}
