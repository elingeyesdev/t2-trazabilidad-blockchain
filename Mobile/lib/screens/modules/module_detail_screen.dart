import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/record_status_badge.dart';
import '../../widgets/information_section.dart';
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
          ],
        ),
        body: SafeArea(
          child: loading
              ? const AppLoading(message: 'Cargando detalle...')
              : error is ApiException && error.statusCode == 404
              ? AppEmptyState(
                  icon: Icons.search_off_rounded,
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
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: OutlinedButton.icon(
                onPressed: _backToList,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Volver a la lista'),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _details(ModuleRecord record) {
    final fields = record.fieldInfo?.details ?? record.details;
    Map<String, String> pick(List<String> keys) => {
      for (final key in keys)
        if (fields.containsKey(key)) key: fields[key]!,
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Icon(
                        widget.module.icon,
                        size: 20,
                        color: AppTheme.forest,
                      ),
                      Text(
                        '${_isLote ? 'Lote' : 'Actividad'} #${record.id}',
                        style: const TextStyle(
                          color: AppTheme.forest,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (record.fieldInfo?.status case final status?)
                    RecordStatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                record.title,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(fontSize: 32, height: 1.15),
              ),
              const SizedBox(height: 28),
              if (_isLote) ...[
                Material(
                  color: AppTheme.forest,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pushNamed(
                      '${AppModule.lotes.route}/${record.id}/historial',
                      arguments: record.title,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.history_rounded,
                            color: AppTheme.ochre,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Historial de actividades',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'El trabajo de este lote, paso a paso.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: AppTheme.ochre,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Información del lote',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _lotOverview(
                  pick(['Cultivo', 'Superficie', 'Actividades pendientes']),
                ),
                const SizedBox(height: 16),
                InformationSection(
                  title: 'Trabajo de campo',
                  icon: Icons.spa_outlined,
                  columns: 2,
                  fields: pick(['Responsable', 'Fecha de siembra']),
                ),
                const SizedBox(height: 16),
                InformationSection(
                  title: 'Origen y trazabilidad',
                  icon: Icons.fingerprint_rounded,
                  fields: pick([
                    'Ubicación',
                    'Código de trazabilidad',
                    'Fecha de creación',
                  ]),
                ),
              ] else ...[
                InformationSection(
                  title: 'Información de la actividad',
                  icon: Icons.assignment_outlined,
                  columns: 2,
                  fields: pick([
                    'Lote',
                    'Cultivo',
                    'Responsable',
                    'Tipo de actividad',
                    'Prioridad',
                  ]),
                ),
                const SizedBox(height: 16),
                InformationSection(
                  title: 'Fechas y seguimiento',
                  icon: Icons.event_outlined,
                  columns: 2,
                  fields: pick(['Fecha planificada', 'Inicio', 'Finalización']),
                ),
                const SizedBox(height: 16),
                InformationSection(
                  title: 'Notas del campo',
                  icon: Icons.notes_rounded,
                  fields: pick(['Observaciones']),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _lotOverview(Map<String, String> fields) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.sage,
      borderRadius: BorderRadius.circular(20),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final paired =
            constraints.maxWidth >= 280 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24;
        return Wrap(
          spacing: 24,
          runSpacing: 20,
          children: [
            for (final field in fields.entries)
              SizedBox(
                width: paired && field.key != 'Cultivo'
                    ? (constraints.maxWidth - 24) / 2
                    : constraints.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: paired && field.key != 'Cultivo' ? 40 : 0,
                      ),
                      child: Text(
                        field.key,
                        style: const TextStyle(
                          color: AppTheme.forest,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      field.value,
                      style: TextStyle(
                        color: AppTheme.forest,
                        fontSize: field.key == 'Cultivo' ? 24 : 20,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.4,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}
