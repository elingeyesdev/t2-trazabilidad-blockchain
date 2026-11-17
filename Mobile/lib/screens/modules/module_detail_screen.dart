import 'package:flutter/material.dart';

import '../../models/actividad_models.dart';
import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/lote_models.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/form_validation.dart';
import '../../widgets/record_status_badge.dart';
import '../../widgets/information_section.dart';
import 'actividad_close_screen.dart';
import 'actividad_form_screen.dart';
import 'lote_form_screen.dart';
import 'module_access_denied.dart';

class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({
    super.key,
    required this.module,
    required this.recordId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.initialNotice,
    this.onLoteUpdated,
    this.onActividadUpdated,
  });

  final AppModule module;
  final int recordId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final String? initialNotice;
  final VoidCallback? onLoteUpdated;
  final VoidCallback? onActividadUpdated;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  late Future<ModuleRecord> _request = _load();
  late String? _notice = widget.initialNotice;
  final _obsFormKey = GlobalKey<FormState>();
  final _obsController = TextEditingController();
  bool _editingObservations = false;
  bool _savingObservations = false;
  ApiException? _obsError;
  bool get _isLote => widget.module == AppModule.lotes;

  @override
  void dispose() {
    _obsController.dispose();
    super.dispose();
  }

  Future<ModuleRecord> _load() =>
      widget.service.loadDetail(widget.module, widget.user, widget.recordId);

  void _refresh() => setState(() {
    _request = _load();
    _request.ignore();
  });

  Future<void> _editLote(ModuleRecord record) async {
    final result = await Navigator.of(context).pushNamed(
      '${AppModule.lotes.route}/${record.id}/editar',
      arguments: record.loteData,
    );
    if (!mounted) return;
    if (result is LoteFormResult) {
      widget.onLoteUpdated?.call();
      setState(() {
        _notice =
            'Los cambios de "${result.record.title}" se guardaron correctamente.';
        _request = _load();
        _request.ignore();
      });
    }
  }

  Future<void> _assignActivity(ModuleRecord record) async {
    final result = await Navigator.of(context).pushNamed(
      '${AppModule.actividades.route}/nueva',
      arguments: LoteOption(
        id: record.id,
        name: record.title,
        cropName: record.fieldInfo?.details['Cultivo'],
      ),
    );
    if (!mounted) return;
    if (result is ActividadFormResult) {
      widget.onActividadUpdated?.call();
      widget.onLoteUpdated?.call();
      setState(() {
        _notice =
            'Se asignó la actividad "${result.record.title}" a este lote.';
        _request = _load();
        _request.ignore();
      });
    }
  }

  Future<void> _closeActivity(ModuleRecord record) async {
    final result = await Navigator.of(context).pushNamed(
      '${AppModule.actividades.route}/${record.id}/cerrar',
      arguments: record.actividadData,
    );
    if (!mounted) return;
    if (result is ActividadCloseResult) {
      widget.onActividadUpdated?.call();
      widget.onLoteUpdated?.call();
      setState(() {
        _editingObservations = false;
        _notice =
            'La actividad "${result.record.title}" fue completada con su fotografía.';
        _request = _load();
        _request.ignore();
      });
    }
  }

  void _startEditingObservations(ModuleRecord record) {
    setState(() {
      _obsController.text = record.actividadData?.observations ?? '';
      _obsError = null;
      _editingObservations = true;
    });
  }

  Future<void> _saveObservations(ModuleRecord record) async {
    if (_savingObservations || !validateForm(_obsFormKey)) return;
    final clean = _obsController.text.trim();
    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.notes_rounded,
      title: '¿Guardar observaciones?',
      message: 'Las notas del campo quedarán visibles en el detalle y la web.',
      details: [
        'Actividad: ${record.title}',
        'Observaciones: ${clean.isEmpty ? 'Sin observaciones' : clean}',
      ],
      confirmLabel: 'Confirmar observaciones',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _savingObservations = true;
      _obsError = null;
    });
    try {
      await widget.service.updateActividadObservaciones(
        widget.user,
        record.id,
        observations: clean,
      );
      if (!mounted) return;
      widget.onActividadUpdated?.call();
      setState(() {
        _savingObservations = false;
        _editingObservations = false;
        _notice = 'Las observaciones de la actividad se guardaron.';
        _request = _load();
        _request.ignore();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _savingObservations = false;
        _obsError = error;
      });
      revealFormErrors(_obsFormKey);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingObservations = false;
        _obsError = const ApiException(
          'No se pudieron guardar las observaciones. Revisa tu conexión e intenta de nuevo.',
        );
      });
    }
  }

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
              if (_notice case final notice?) ...[
                const SizedBox(height: 20),
                AppNotice(tone: AppNoticeTone.success, message: notice),
              ],
              const SizedBox(height: 28),
              if (_isLote) ...[
                if (record.loteData?.isClosed != true &&
                    (LotePermissions.canEdit(widget.user) ||
                        ActividadPermissions.canAssign(widget.user))) ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (LotePermissions.canEdit(widget.user))
                        FilledButton.icon(
                          onPressed: () => _editLote(record),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Editar lote'),
                        ),
                      if (ActividadPermissions.canAssign(widget.user))
                        OutlinedButton.icon(
                          onPressed: () => _assignActivity(record),
                          icon: const Icon(Icons.assignment_add, size: 18),
                          label: const Text('Asignar actividad'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
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
                if (ActividadPermissions.canClose(
                  widget.user,
                  record.actividadData,
                )) ...[
                  FilledButton.icon(
                    onPressed: () => _closeActivity(record),
                    icon: const Icon(Icons.task_alt_rounded, size: 18),
                    label: const Text('Completar y cerrar actividad'),
                  ),
                  const SizedBox(height: 16),
                ],
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
                  fields: {
                    ...pick(['Observaciones']),
                    'Resultado': ?record.actividadData?.resultado,
                  },
                ),
                if (ActividadPermissions.canAddObservations(widget.user)) ...[
                  const SizedBox(height: 16),
                  if (_editingObservations)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.line),
                      ),
                      child: Form(
                        key: _obsFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Observaciones de campo',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const ValueKey('actividad.observaciones'),
                              controller: _obsController,
                              scrollPadding: formScrollPadding(context),
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              forceErrorText: _obsError
                                  ?.validationErrors['observaciones']
                                  ?.join('\n'),
                              enabled: !_savingObservations,
                              maxLines: 3,
                              maxLength: 250,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Observaciones',
                                hintText:
                                    'Describe avances o novedades de la tarea',
                              ),
                              onChanged: (_) {
                                if (_obsError != null) {
                                  setState(() => _obsError = null);
                                }
                              },
                            ),
                            if (_obsError != null &&
                                (_obsError!.validationErrors.isEmpty ||
                                    _obsError!.validationErrors.keys.any(
                                      (k) => k != 'observaciones',
                                    ))) ...[
                              const SizedBox(height: 12),
                              AppNotice(
                                tone: AppNoticeTone.error,
                                message: _obsError!.message,
                              ),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: _savingObservations
                                      ? null
                                      : () => _saveObservations(record),
                                  child: Text(
                                    _savingObservations
                                        ? 'Guardando...'
                                        : 'Guardar observaciones',
                                  ),
                                ),
                                TextButton(
                                  onPressed: _savingObservations
                                      ? null
                                      : () => setState(() {
                                          _editingObservations = false;
                                          _obsError = null;
                                        }),
                                  child: const Text('Cancelar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _startEditingObservations(record),
                      icon: const Icon(Icons.edit_note_rounded, size: 20),
                      label: Text(
                        (record.actividadData?.observations ?? '').isEmpty
                            ? 'Añadir observaciones'
                            : 'Editar observaciones',
                      ),
                    ),
                ],
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
