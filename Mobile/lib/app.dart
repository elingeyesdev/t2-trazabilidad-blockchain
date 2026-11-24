import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'config/api_config.dart';
import 'controllers/auth_controller.dart';
import 'models/actividad_models.dart';
import 'models/incidente_models.dart';
import 'models/lote_models.dart';
import 'models/pedido_models.dart';
import 'models/qr_envio_models.dart';
import 'navigation/app_module.dart';
import 'navigation/app_routes.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/modules/actividad_close_screen.dart';
import 'screens/modules/actividad_form_screen.dart';
import 'screens/modules/almacen_detail_screen.dart';
import 'screens/modules/cosecha_form_screen.dart';
import 'screens/modules/entrega_detail_screen.dart';
import 'screens/modules/entregas_screen.dart';
import 'screens/modules/envio_qr_detail_screen.dart';
import 'screens/modules/incidente_form_screen.dart';
import 'screens/modules/inventario_alertas_screen.dart';
import 'screens/modules/lote_activity_history_screen.dart';
import 'screens/modules/lote_form_screen.dart';
import 'screens/modules/module_access_denied.dart';
import 'screens/modules/module_detail_screen.dart';
import 'screens/modules/module_screen.dart';
import 'screens/modules/movimientos_screen.dart';
import 'screens/modules/pedido_detail_screen.dart';
import 'screens/modules/pedido_form_screen.dart';
import 'screens/modules/pedidos_screen.dart';
import 'screens/modules/planta_procesamiento_screen.dart';
import 'screens/modules/planta_recepcion_detail_screen.dart';
import 'screens/modules/planta_recepciones_screen.dart';
import 'screens/modules/planta_tarea_detail_screen.dart';
import 'screens/modules/planta_tareas_screen.dart';
import 'screens/modules/qr_scanner_screen.dart';
import 'screens/modules/usuario_detail_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/public/trazabilidad_lookup_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/module_service.dart';
import 'services/offline_store.dart';
import 'services/pending_queue.dart';
import 'services/task_notifier.dart';
import 'services/session_storage.dart';
import 'theme/app_theme.dart';
import 'widgets/app_error_state.dart';
import 'widgets/app_loading.dart';
import 'widgets/location_input_field.dart';

class AgroFusionApp extends StatefulWidget {
  const AgroFusionApp({
    super.key,
    this.apiClient,
    this.sessionStorage = const SessionStorage(),
    this.requestLocation,
    this.capturePhoto,
    this.selectEvidenceFile,
    this.offlineStore,
    this.trazabilidadCameraBuilder,
  });

  final ApiClient? apiClient;
  final SessionStorage sessionStorage;
  final Future<DeviceLocation?> Function()? requestLocation;
  final Future<XFile?> Function()? capturePhoto;
  final Future<XFile?> Function()? selectEvidenceFile;

  /// Si es nulo (pruebas), no se guarda nada para trabajar sin conexión.
  final OfflineStore? offlineStore;
  final QrCameraBuilder? trazabilidadCameraBuilder;

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
        offlineStore: widget.offlineStore,
      );
  late final PendingQueue? _pending = widget.offlineStore == null
      ? null
      : PendingQueue(widget.offlineStore!);
  late final TaskNotifier? _notifier = widget.offlineStore == null
      ? null
      : TaskNotifier(widget.offlineStore!);
  late final AuthController _auth = AuthController(
    AuthService(_api, widget.sessionStorage),
  );
  final ValueNotifier<int> _loteUpdates = ValueNotifier(0);
  final ValueNotifier<int> _actividadUpdates = ValueNotifier(0);
  final ValueNotifier<int> _cosechaUpdates = ValueNotifier(0);
  final ValueNotifier<int> _plantaUpdates = ValueNotifier(0);
  final ValueNotifier<int> _recepcionUpdates = ValueNotifier(0);
  final ValueNotifier<int> _pedidosUpdates = ValueNotifier(0);
  final ValueNotifier<int> _entregasUpdates = ValueNotifier(0);
  final ValueNotifier<int> _usuarioUpdates = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_onAuthChanged);
    unawaited(_pending?.load().then((_) => _syncPending()));
    unawaited(_auth.restoreSession());
  }

  bool _hadUser = false;
  final _navigatorKey = GlobalKey<NavigatorState>();

  void _onAuthChanged() {
    final user = _auth.user;
    if (user == null && _hadUser) {
      unawaited(widget.offlineStore?.clearCache());
      // Quien entre después debe empezar en el inicio, no en la pantalla que
      // dejó abierta la cuenta anterior (por ejemplo, el perfil).
      if (_auth.isLoggingOut) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _navigatorKey.currentState?.popUntil((route) => route.isFirst),
        );
      }
    }
    if (user != null && !_hadUser) unawaited(_syncPending());
    _hadUser = user != null;
  }

  Future<void> _syncPending() async {
    final user = _auth.user;
    if (user == null || _pending == null) return;
    final service = ModuleService(_api);
    final sent = await _pending.flush(service, user);
    if (sent > 0) {
      _loteUpdates.value++;
      _actividadUpdates.value++;
      _cosechaUpdates.value++;
    }
    await _notifier?.check(service, user);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _auth.user != null &&
        !_auth.shouldSuppressResumeRestore) {
      unawaited(_auth.restoreSession());
      unawaited(_syncPending());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loteUpdates.dispose();
    _actividadUpdates.dispose();
    _cosechaUpdates.dispose();
    _plantaUpdates.dispose();
    _recepcionUpdates.dispose();
    _pedidosUpdates.dispose();
    _entregasUpdates.dispose();
    _usuarioUpdates.dispose();
    _auth.removeListener(_onAuthChanged);
    _pending?.dispose();
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
      navigatorKey: _navigatorKey,
      title: 'AgroFusion',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (_) => _sessionGate(
          () => HomeScreen(
            key: ValueKey(_auth.user!.id),
            user: _auth.user!,
            onLogout: _auth.logout,
            pending: _pending,
            offlineData: _api.servedFromCache,
            onSync: _syncPending,
            // Con almacenamiento local (la app real) se muestran las tareas del día;
            // las pruebas de pantallas no esperan esa consulta adicional.
            service: _pending == null ? null : ModuleService(_api),
          ),
          requiresAuthentication: true,
        ),
        AppRoutes.register: (_) =>
            _sessionGate(() => RegisterScreen(controller: _auth)),
        AppRoutes.trazabilidadPublica: (_) => TrazabilidadLookupScreen(
          cameraBuilder: widget.trazabilidadCameraBuilder,
        ),
        AppRoutes.profile: (_) => _sessionGate(
          () => ProfileScreen(controller: _auth),
          requiresAuthentication: true,
        ),
        for (final module in AppModule.values)
          module.route: (_) => _sessionGate(
            () => module == AppModule.tareasPlanta
                ? PlantaTareasScreen(
                    key: ValueKey(_auth.user),
                    user: _auth.user!,
                    service: ModuleService(_api),
                    onRefreshPermissions: _auth.restoreSession,
                    updates: _plantaUpdates,
                  )
                : module == AppModule.recepcionesPlanta
                ? PlantaRecepcionesScreen(
                    key: ValueKey(_auth.user),
                    user: _auth.user!,
                    service: ModuleService(_api),
                    onRefreshPermissions: _auth.restoreSession,
                    updates: _recepcionUpdates,
                  )
                : module == AppModule.movimientos
                ? MovimientosScreen(
                    key: ValueKey(_auth.user),
                    user: _auth.user!,
                    service: ModuleService(_api),
                    onRefreshPermissions: _auth.restoreSession,
                  )
                : module == AppModule.pedidos &&
                      (PedidoPermissions.canCreateAgricola(_auth.user!) ||
                          (!PedidoPermissions.canViewAgricola(_auth.user!) &&
                              PedidoPermissions.canViewDistribucion(
                                _auth.user!,
                              )))
                ? PedidosScreen(
                    key: ValueKey(_auth.user),
                    user: _auth.user!,
                    service: ModuleService(_api),
                    onRefreshPermissions: _auth.restoreSession,
                    updates: _pedidosUpdates,
                  )
                : ModuleScreen(
                    key: ValueKey(_auth.user),
                    module: module,
                    user: _auth.user!,
                    service: ModuleService(_api),
                    onRefreshPermissions: _auth.restoreSession,
                    loteUpdates: module == AppModule.lotes
                        ? _loteUpdates
                        : null,
                    actividadUpdates: module == AppModule.actividades
                        ? _actividadUpdates
                        : null,
                    cosechaUpdates: module == AppModule.producciones
                        ? _cosechaUpdates
                        : null,
                    usuarioUpdates: module == AppModule.usuarios
                        ? _usuarioUpdates
                        : null,
                  ),
            requiresAuthentication: true,
            module: module,
          ),
      },
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '');
        if (uri == null ||
            uri.hasScheme ||
            uri.hasAuthority ||
            uri.hasQuery ||
            uri.hasFragment) {
          return null;
        }
        if (uri.pathSegments case ['modules', 'usuarios', final rawId]) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => UsuarioDetailScreen(
                key: ValueKey(_auth.user),
                usuarioId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                onUsuarioUpdated: () => _usuarioUpdates.value++,
              ),
              requiresAuthentication: true,
              module: AppModule.usuarios,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'incidentes', 'nuevo']) {
          final args = settings.arguments;
          if (args is! IncidenteFormArgs) return null;
          return MaterialPageRoute<IncidenteRecord?>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => IncidenteFormScreen(
                key: ValueKey(_auth.user),
                args: args,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
              ),
              requiresAuthentication: true,
            ),
          );
        }
        if (uri.pathSegments case [
          'modules',
          'entregas',
          'ruta',
          final rawId,
        ]) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => EntregaDetailScreen(
                key: ValueKey(_auth.user),
                rutaId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                onEntregaUpdated: () => _entregasUpdates.value++,
              ),
              requiresAuthentication: true,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'entregas']) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => EntregasScreen(
                key: ValueKey(_auth.user),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                updates: _entregasUpdates,
              ),
              requiresAuthentication: true,
            ),
          );
        }
        if (uri.pathSegments case [
          'modules',
          'envios',
          final rawTipo,
          final rawId,
        ]) {
          final tipo = EnvioTipo.fromValue(rawTipo);
          final id = int.tryParse(rawId);
          if (tipo == null || id == null || id <= 0) return null;
          final initialResolution = settings.arguments is QrResolucionResult
              ? settings.arguments as QrResolucionResult
              : null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => EnvioQrDetailScreen(
                key: ValueKey(_auth.user),
                tipo: tipo,
                envioId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                initialResolution: initialResolution,
                onRecepcionConfirmed: () {
                  _pedidosUpdates.value++;
                  _entregasUpdates.value++;
                },
              ),
              requiresAuthentication: true,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'qr']) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => QrScannerScreen(
                key: ValueKey(_auth.user),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
              ),
              requiresAuthentication: true,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'pedidos', 'gestion']) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => PedidosScreen(
                key: ValueKey(_auth.user),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                updates: _pedidosUpdates,
              ),
              requiresAuthentication: true,
              module: AppModule.pedidos,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'pedidos', 'nuevo']) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => PedidoFormScreen(
                key: ValueKey(
                  'pedido-form:${_auth.user?.id}:${_auth.user?.roles.join(",")}',
                ),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                onPedidoCreated: () => _pedidosUpdates.value++,
              ),
              requiresAuthentication: true,
              module: AppModule.pedidos,
            ),
          );
        }
        if (uri.pathSegments case [
          'modules',
          'pedidos',
          final rawTipo,
          final rawId,
        ]) {
          final tipo = PedidoTipo.fromValue(rawTipo);
          final id = int.tryParse(rawId);
          if (tipo == null || id == null || id <= 0) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => PedidoDetailScreen(
                key: ValueKey(_auth.user),
                tipo: tipo,
                pedidoId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                updates: _pedidosUpdates,
                onPedidoUpdated: () => _pedidosUpdates.value++,
              ),
              requiresAuthentication: true,
              module: AppModule.pedidos,
            ),
          );
        }
        if (uri.pathSegments case [
          'modules',
          'planta',
          'lotes-produccion',
          final rawId,
        ]) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => PlantaProcesamientoScreen(
                key: ValueKey(_auth.user),
                loteProduccionId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
              ),
              requiresAuthentication: true,
            ),
          );
        }
        if (uri.pathSegments case [
          'modules',
          'planta',
          'recepciones',
          final rawId,
        ]) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => PlantaRecepcionDetailScreen(
                key: ValueKey(_auth.user),
                pedidoId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                onRecepcionUpdated: () => _recepcionUpdates.value++,
              ),
              requiresAuthentication: true,
              module: AppModule.recepcionesPlanta,
            ),
          );
        }
        if (uri.pathSegments case [
          'modules',
          'planta',
          'tareas',
          final rawId,
        ]) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => PlantaTareaDetailScreen(
                key: ValueKey(_auth.user),
                asignacionId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                onTareaUpdated: () => _plantaUpdates.value++,
              ),
              requiresAuthentication: true,
              module: AppModule.tareasPlanta,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'actividades', 'nueva']) {
          final loteArg = settings.arguments is LoteOption
              ? settings.arguments as LoteOption
              : null;
          return MaterialPageRoute<ActividadFormResult?>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => ActividadFormScreen(
                key: ValueKey(_auth.user),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                initialLoteId: loteArg?.id,
                initialLoteName: loteArg?.name,
              ),
              requiresAuthentication: true,
              module: AppModule.actividades,
            ),
          );
        }
        if (uri.pathSegments case [
          'modules',
          'actividades',
          final rawId,
          'cerrar',
        ]) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<ActividadCloseResult?>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => ActividadCloseScreen(
                key: ValueKey(
                  'close:$id:${_auth.user?.id}:${_auth.user?.roles.join(",")}:${_auth.user?.permissions.join(",")}',
                ),
                actividadId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                initialData: settings.arguments is ActividadEditableData
                    ? settings.arguments as ActividadEditableData
                    : null,
                capturePhoto: widget.capturePhoto,
                selectFile: widget.selectEvidenceFile,
                onExternalPicker: _auth.runExternalPicker,
                pending: _pending,
              ),
              requiresAuthentication: true,
              module: AppModule.actividades,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'lotes', 'nuevo']) {
          return MaterialPageRoute<LoteFormResult?>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => LoteFormScreen(
                key: ValueKey(_auth.user),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                requestLocation: widget.requestLocation,
              ),
              requiresAuthentication: true,
              module: AppModule.lotes,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'lotes', final rawId, 'editar']) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<LoteFormResult?>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => LoteFormScreen(
                key: ValueKey(_auth.user),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                loteId: id,
                initialData: settings.arguments is LoteEditableData
                    ? settings.arguments as LoteEditableData
                    : null,
                requestLocation: widget.requestLocation,
              ),
              requiresAuthentication: true,
              module: AppModule.lotes,
            ),
          );
        }
        if (uri.pathSegments case [
          'modules',
          'lotes',
          final rawId,
          'historial',
        ]) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => LoteActivityHistoryScreen(
                key: ValueKey(_auth.user),
                loteId: id,
                loteName: settings.arguments is String
                    ? settings.arguments as String
                    : null,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
              ),
              requiresAuthentication: true,
              module: AppModule.lotes,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'almacenes', 'alertas']) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => InventarioAlertasScreen(
                key: ValueKey(_auth.user),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                initialAlmacenId: settings.arguments is int
                    ? settings.arguments as int
                    : null,
              ),
              requiresAuthentication: true,
              module: AppModule.almacenes,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'almacenes', final rawId]) {
          final id = int.tryParse(rawId);
          if (id == null || id <= 0) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => AlmacenDetailScreen(
                key: ValueKey(_auth.user),
                almacenId: id,
                almacenName: settings.arguments is String
                    ? settings.arguments as String
                    : null,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
              ),
              requiresAuthentication: true,
              module: AppModule.almacenes,
            ),
          );
        }
        if (uri.pathSegments case ['modules', 'producciones', 'nueva']) {
          final loteArg = settings.arguments is LoteOption
              ? settings.arguments as LoteOption
              : null;
          return MaterialPageRoute<CosechaFormResult?>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => CosechaFormScreen(
                key: ValueKey(_auth.user),
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                initialLoteId: loteArg?.id,
                initialLoteName: loteArg?.name,
                pending: _pending,
              ),
              requiresAuthentication: true,
              module: AppModule.producciones,
            ),
          );
        }
        if (uri.pathSegments case ['modules', final endpoint, final rawId]) {
          final module = switch (endpoint) {
            'lotes' => AppModule.lotes,
            'actividades' => AppModule.actividades,
            'producciones' => AppModule.producciones,
            _ => null,
          };
          final id = int.tryParse(rawId);
          if (module == null || id == null || id <= 0) return null;
          final detailArgs = settings.arguments is ActivityDetailArgs
              ? settings.arguments as ActivityDetailArgs
              : null;
          final initialNotice =
              detailArgs?.initialNotice ??
              (settings.arguments is String
                  ? settings.arguments as String
                  : null);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _sessionGate(
              () => ModuleDetailScreen(
                key: ValueKey(_auth.user),
                module: module,
                recordId: id,
                user: _auth.user!,
                service: ModuleService(_api),
                onRefreshPermissions: _auth.restoreSession,
                initialNotice: initialNotice,
                returnToLoteId: detailArgs?.returnToLoteId,
                returnToLoteName: detailArgs?.returnToLoteName,
                onLoteUpdated: module == AppModule.lotes
                    ? () => _loteUpdates.value++
                    : null,
                onActividadUpdated: () => _actividadUpdates.value++,
              ),
              requiresAuthentication: true,
              module: module,
            ),
          );
        }
        return null;
      },
    );
  }
}
