import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({
    super.key,
    required this.module,
    required this.recordId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final AppModule module;
  final int recordId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  late Future<ModuleRecord> _request = _load();
  bool get _isLote => widget.module == AppModule.lotes;

  Future<ModuleRecord> _load() =>
      widget.service.loadDetail(widget.module, widget.user, widget.recordId);

  void _refresh() => setState(() {
    _request = _load();
    _request.ignore();
  });

  void _backToList() {
    final navigator = Navigator.of(context);
    final listRoute = widget.module.route;
    var foundList = false;
    navigator.popUntil((route) {
      foundList = route.settings.name == listRoute;
      return foundList || route.isFirst;
    });
    if (!foundList) {
      navigator.pushNamed(listRoute);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ModuleRecord>(
    future: _request,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final error = snapshot.error;
      if (!loading && error is ApiException && error.statusCode == 403) {
        return ModuleAccessDenied(
          title: _isLote ? 'Detalle del lote' : 'Detalle de actividad',
          onRefreshPermissions: widget.onRefreshPermissions,
        );
      }
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Volver a la lista',
            onPressed: _backToList,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(_isLote ? 'Detalle del lote' : 'Detalle de actividad'),
          actions: [
            IconButton(
              tooltip: 'Actualizar detalle',
              onPressed: loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: loading
              ? const AppLoading(message: 'Cargando detalle...')
              : error is ApiException && error.statusCode == 404
              ? const AppEmptyState(
                  icon: Icons.search_off_rounded,
                  tone: AppTheme.maizeSoft,
                  ink: Color(0xFF5F4100),
                  title: 'El registro ya no está disponible',
                  message: 'Vuelve a la lista y actualiza la información.',
                )
              : snapshot.hasError
              ? AppErrorState(
                  message: error is ApiException
                      ? error.message
                      : 'No se pudo consultar la información.',
                  onRetry: _refresh,
                )
              : _details(snapshot.requireData),
        ),
        bottomNavigationBar: BottomActionBar(
          child: OutlinedButton.icon(
            onPressed: _backToList,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Volver a la lista'),
          ),
        ),
      );
    },
  );

  Widget _details(ModuleRecord record) {
    final look = widget.module.look;
    final fields = (record.fieldInfo?.details ?? record.details).entries
        .where((field) => field.key != 'Identificador')
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: look.tone,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppTheme.ink, width: 2),
                  boxShadow: AppTheme.stamp(5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ModuleMark(widget.module, size: 48, solid: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_isLote ? 'Lote' : 'Actividad'} #${record.id}',
                            style: TextStyle(
                              color: look.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        record.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (record.fieldInfo?.status != null) ...[
                      const SizedBox(height: 14),
                      RecordStatusBadge(status: record.fieldInfo!.status!),
                    ],
                  ],
                ),
              ),
              if (_isLote) ...[
                const SizedBox(height: 22),
                PressableCard(
                  onTap: () => Navigator.of(context).pushNamed(
                    '${AppModule.lotes.route}/${record.id}/historial',
                    arguments: record.title,
                  ),
                  color: AppTheme.maizeSoft,
                  child: Row(
                    children: [
                      const IconMedallion(
                        icon: Icons.history_rounded,
                        tone: AppTheme.maize,
                        ink: AppTheme.ink,
                        size: 52,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Historial de actividades',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Consulta el trabajo registrado en este lote.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppTheme.ink),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 32,
                        color: AppTheme.ink,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 30),
              SectionTitle(
                _isLote
                    ? 'Información del lote'
                    : 'Información de la actividad',
                color: look.tone,
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: AppTheme.ink, width: 2),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      DetailField(label: fields[i].key, value: fields[i].value),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
