import 'package:flutter/material.dart';

import '../../models/actividad_models.dart';
import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/lote_models.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/form_validation.dart';
import '../../widgets/record_status_badge.dart';
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
    final fields = <MapEntry<String, String>>[
      ...(record.fieldInfo?.details ?? record.details).entries.where(
        (field) =>
            field.key != 'Identificador' &&
            (record.fieldInfo?.status == null || field.key != 'Estado'),
      ),
      if (!_isLote && record.actividadData?.resultado != null)
        MapEntry('Resultado', record.actividadData!.resultado!),
    ];
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              if (_notice case final notice?) ...[
                const SizedBox(height: 20),
                AppNotice(tone: AppNoticeTone.success, message: notice),
              ],
              if (_isLote) ...[
                if (record.loteData?.isClosed != true &&
                    (LotePermissions.canEdit(widget.user) ||
                        ActividadPermissions.canAssign(widget.user))) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (LotePermissions.canEdit(widget.user))
                        FilledButton.icon(
                          onPressed: () => _editLote(record),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar lote'),
                        ),
                      if (ActividadPermissions.canAssign(widget.user))
                        OutlinedButton.icon(
                          onPressed: () => _assignActivity(record),
                          icon: const Icon(Icons.assignment_add),
                          label: const Text('Asignar actividad'),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
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
              ] else if (ActividadPermissions.canClose(
                widget.user,
                record.actividadData,
              )) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _closeActivity(record),
                  icon: const Icon(Icons.task_alt_rounded),
                  label: const Text('Completar y cerrar actividad'),
                ),
              ],
              const SizedBox(height: 28),
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
              if (!_isLote &&
                  (record.actividadData?.consumos.isNotEmpty ?? false)) ...[
                const SizedBox(height: 24),
                SectionTitle('Insumos utilizados', color: look.tone),
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
                      for (
                        var i = 0;
                        i < record.actividadData!.consumos.length;
                        i++
                      ) ...[
                        if (i > 0) const Divider(height: 1),
                        DetailField(
                          label: record.actividadData!.consumos[i].name,
                          value: record
                              .actividadData!
                              .consumos[i]
                              .formattedQuantity,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (!_isLote &&
                  ActividadPermissions.canAddObservations(widget.user)) ...[
                const SizedBox(height: 20),
                if (_editingObservations)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.ink, width: 2),
                    ),
                    child: Form(
                      key: _obsFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Observaciones de campo',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 14),
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
                            style: const TextStyle(fontSize: 18),
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
                            runSpacing: 10,
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
                              OutlinedButton(
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
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(
                      (record.actividadData?.observations ?? '').isEmpty
                          ? 'Añadir observaciones'
                          : 'Editar observaciones',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
