import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/actividad_models.dart';
import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/cosecha_models.dart';
import '../../models/lote_models.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../navigation/app_routes.dart';
import '../../services/module_service.dart';
import '../../services/pending_queue.dart';
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

class ActivityDetailArgs {
  const ActivityDetailArgs({
    this.initialNotice,
    this.returnToLoteId,
    this.returnToLoteName,
  });

  final String? initialNotice;
  final int? returnToLoteId;
  final String? returnToLoteName;
}

class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({
    super.key,
    required this.module,
    required this.recordId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.initialNotice,
    this.returnToLoteId,
    this.returnToLoteName,
    this.onLoteUpdated,
    this.onActividadUpdated,
  });

  final AppModule module;
  final int recordId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final String? initialNotice;
  final int? returnToLoteId;
  final String? returnToLoteName;
  final VoidCallback? onLoteUpdated;
  final VoidCallback? onActividadUpdated;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  late Future<ModuleRecord> _request = _load();
  late String? _notice = widget.initialNotice;
  Future<Uint8List>? _evidenceRequest;
  int? _evidenceActivityId;
  final _obsFormKey = GlobalKey<FormState>();
  final _obsController = TextEditingController();
  bool _editingObservations = false;
  bool _savingObservations = false;
  ApiException? _obsError;
  bool _editingResponsable = false;
  bool _loadingResponsables = false;
  bool _savingResponsable = false;
  List<ResponsableOption> _responsables = const [];
  int? _selectedResponsableId;
  String? _responsableError;

  bool get _isLote => widget.module == AppModule.lotes;
  bool get _isActividad => widget.module == AppModule.actividades;
  bool get _isCosecha => widget.module == AppModule.producciones;

  String get _screenTitle => switch (widget.module) {
    AppModule.lotes => 'Detalle del lote',
    AppModule.producciones => 'Detalle de cosecha',
    _ => 'Detalle de actividad',
  };

  String get _recordPrefix => switch (widget.module) {
    AppModule.lotes => 'Lote',
    AppModule.producciones => 'Cosecha',
    _ => 'Actividad',
  };

  @override
  void dispose() {
    _obsController.dispose();
    super.dispose();
  }

  Future<ModuleRecord> _load() =>
      widget.service.loadDetail(widget.module, widget.user, widget.recordId);

  void _refresh() => setState(() {
    _evidenceRequest = null;
    _evidenceActivityId = null;
    _request = _load();
    _request.ignore();
  });

  Future<Uint8List>? _ensureEvidenceRequest(ModuleRecord record) {
    final actividad = record.actividadData;
    if (_isLote ||
        actividad == null ||
        !actividad.isCompleted ||
        !actividad.isEvidenceAvailable) {
      return null;
    }
    if (_evidenceRequest == null || _evidenceActivityId != record.id) {
      _evidenceActivityId = record.id;
      _evidenceRequest = widget.service.loadActividadEvidence(
        widget.user,
        record.id,
      );
      _evidenceRequest!.ignore();
    }
    return _evidenceRequest;
  }

  void _retryEvidence(int actividadId) => setState(() {
    _evidenceActivityId = actividadId;
    _evidenceRequest = widget.service.loadActividadEvidence(
      widget.user,
      actividadId,
    );
    _evidenceRequest!.ignore();
  });

  Future<void> _openEvidenceViewer(Uint8List bytes, String title) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              leading: IconButton(
                tooltip: 'Cerrar vista ampliada',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text(title, overflow: TextOverflow.ellipsis),
            ),
            body: Center(
              child: InteractiveViewer(
                key: const ValueKey('actividad.evidencia.viewer'),
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    size: 72,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _editLote(ModuleRecord record) async {
    final result = await Navigator.of(
      context,
    ).pushNamed(AppRoutes.loteEditar(record.id), arguments: record.loteData);
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
      AppRoutes.nueva(AppModule.actividades),
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
      AppRoutes.actividadCerrar(record.id),
      arguments: record.actividadData,
    );
    if (!mounted) return;
    if (result is QueuedResult) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
    if (result is ActividadCloseResult) {
      widget.onActividadUpdated?.call();
      widget.onLoteUpdated?.call();
      setState(() {
        _editingObservations = false;
        _evidenceRequest = null;
        _evidenceActivityId = null;
        _notice =
            'La actividad "${result.record.title}" fue completada con su fotografía.';
        _request = _load();
        _request.ignore();
      });
    }
  }

  Future<void> _startReassignResponsable(ModuleRecord record) async {
    final currentId = record.actividadData?.responsableId;
    setState(() {
      _editingResponsable = true;
      _loadingResponsables = true;
      _responsableError = null;
      _selectedResponsableId = currentId;
    });
    try {
      final list = await widget.service.loadResponsables(widget.user);
      if (!mounted) return;
      setState(() {
        _responsables = list;
        if (_selectedResponsableId == null ||
            !list.any((item) => item.id == _selectedResponsableId)) {
          _selectedResponsableId = list.isNotEmpty ? list.first.id : null;
        }
        _loadingResponsables = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingResponsables = false;
        _responsableError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingResponsables = false;
        _responsableError = 'No se pudo cargar el equipo de campo.';
      });
    }
  }

  Future<void> _saveResponsable(ModuleRecord record) async {
    if (_savingResponsable) return;
    final targetId = _selectedResponsableId;
    if (targetId == null) {
      setState(() => _responsableError = 'Selecciona un responsable.');
      return;
    }
    if (targetId == record.actividadData?.responsableId) {
      setState(() {
        _editingResponsable = false;
        _responsableError = null;
      });
      return;
    }
    String selectedName = 'Responsable #$targetId';
    for (final item in _responsables) {
      if (item.id == targetId) {
        selectedName = item.displayLabel;
        break;
      }
    }
    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.swap_horiz_rounded,
      title: '¿Cambiar responsable?',
      message: 'La actividad pasará a estar asignada al trabajador elegido.',
      details: [
        'Actividad: ${record.title}',
        'Nuevo responsable: $selectedName',
      ],
      confirmLabel: 'Confirmar cambio',
    );
    if (!mounted || !confirmed) return;

    setState(() {
      _savingResponsable = true;
      _responsableError = null;
    });
    try {
      await widget.service.reassignActividad(
        widget.user,
        record.id,
        responsableId: targetId,
      );
      if (!mounted) return;
      widget.onActividadUpdated?.call();
      setState(() {
        _savingResponsable = false;
        _editingResponsable = false;
        _notice = 'Responsable actualizado a $selectedName.';
        _request = _load();
        _request.ignore();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _savingResponsable = false;
        _responsableError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingResponsable = false;
        _responsableError =
            'No se pudo cambiar el responsable. Revisa tu conexión e intenta de nuevo.';
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

  void _openLoteHistory(int loteId, String? loteName) {
    final navigator = Navigator.of(context);
    final historyRoute = AppRoutes.loteHistorial(loteId);
    if (widget.returnToLoteId == loteId) {
      var foundHistory = false;
      navigator.popUntil((route) {
        foundHistory = route.settings.name == historyRoute;
        return foundHistory || route.isFirst;
      });
      if (!foundHistory) {
        navigator.pushNamed(historyRoute, arguments: loteName);
      }
      return;
    }
    navigator.pushNamed(historyRoute, arguments: loteName);
  }

  void _backToList() {
    if (!_isLote && widget.returnToLoteId != null) {
      _openLoteHistory(widget.returnToLoteId!, widget.returnToLoteName);
      return;
    }
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
          title: _screenTitle,
          onRefreshPermissions: widget.onRefreshPermissions,
        );
      }
      final returningToHistory = _isActividad && widget.returnToLoteId != null;
      final backLabel = returningToHistory
          ? 'Volver al historial del lote'
          : 'Volver a la lista';
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: backLabel,
            onPressed: _backToList,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(_screenTitle),
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
              ? const AppLoading(
                  message: 'Cargando detalle...',
                  shape: LoadingShape.detail,
                )
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
            label: Text(backLabel),
          ),
        ),
      );
    },
  );

  Widget _details(ModuleRecord record) {
    final look = widget.module.look;
    final actividad = record.actividadData;
    final cosecha = record.cosechaData;
    final fields = _isCosecha && cosecha != null
        ? <MapEntry<String, String>>[
            MapEntry('Lote', cosecha.loteLabel),
            MapEntry(
              'Fecha de cosecha',
              cosecha.fechaCosecha ?? 'Sin registrar',
            ),
            MapEntry('Cantidad registrada', cosecha.formattedQuantity),
            MapEntry(
              'Presentación',
              cosecha.calibreNombre ?? 'Sin presentación asignada',
            ),
            MapEntry(
              'Observaciones',
              cosecha.observaciones ?? 'Sin observaciones',
            ),
          ]
        : <MapEntry<String, String>>[
            ...(record.fieldInfo?.details ?? record.details).entries.where(
              (field) =>
                  field.key != 'Identificador' &&
                  (record.fieldInfo?.status == null || field.key != 'Estado'),
            ),
            if (_isActividad &&
                actividad != null &&
                actividad.isCompleted &&
                actividad.closingResponsibleName != null)
              MapEntry(
                'Responsable de cierre',
                actividad.closingResponsibleName!,
              ),
            if (_isActividad && actividad != null) ...[
              if (actividad.resultado != null)
                MapEntry('Resultado', actividad.resultado!)
              else if (actividad.isCompleted)
                const MapEntry('Resultado', 'Sin resultado registrado'),
            ],
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
                  border: Border.all(color: AppTheme.border, width: 1),
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
                            '$_recordPrefix #${record.id}',
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
                    AppRoutes.loteHistorial(record.id),
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
              ] else if (_isActividad &&
                  actividad != null &&
                  !actividad.isCompleted) ...[
                if (ActividadPermissions.canClose(widget.user, actividad) ||
                    ActividadPermissions.canReassign(
                      widget.user,
                      actividad,
                    )) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (ActividadPermissions.canClose(widget.user, actividad))
                        FilledButton.icon(
                          onPressed: () => _closeActivity(record),
                          icon: const Icon(Icons.task_alt_rounded),
                          label: const Text('Completar y cerrar actividad'),
                        ),
                      if (ActividadPermissions.canReassign(
                            widget.user,
                            actividad,
                          ) &&
                          !_editingResponsable)
                        OutlinedButton.icon(
                          key: const ValueKey('actividad.cambiar_responsable'),
                          onPressed: () => _startReassignResponsable(record),
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Cambiar responsable'),
                        ),
                    ],
                  ),
                ],
                if (ActividadPermissions.canReassign(widget.user, actividad) &&
                    !ActividadPermissions.canClose(widget.user, actividad) &&
                    !_editingResponsable) ...[
                  const SizedBox(height: 12),
                  const AppNotice(
                    tone: AppNoticeTone.info,
                    message:
                        'Solo el responsable asignado puede cerrar esta actividad con evidencia. Puedes cambiar el responsable arriba si necesitas reasignarla.',
                  ),
                ],
                if (_editingResponsable &&
                    ActividadPermissions.canReassign(
                      widget.user,
                      actividad,
                    )) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.border, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Cambiar responsable',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        if (_loadingResponsables)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text('Cargando equipo disponible...'),
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownButtonFormField<int>(
                            key: const ValueKey('actividad.responsable_select'),
                            initialValue:
                                _responsables.any(
                                  (item) => item.id == _selectedResponsableId,
                                )
                                ? _selectedResponsableId
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Nuevo responsable',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            items: _responsables
                                .map(
                                  (item) => DropdownMenuItem<int>(
                                    value: item.id,
                                    child: Text(
                                      item.displayLabel,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _savingResponsable
                                ? null
                                : (value) => setState(() {
                                    _selectedResponsableId = value;
                                    _responsableError = null;
                                  }),
                          ),
                        if (_responsableError != null) ...[
                          const SizedBox(height: 12),
                          AppNotice(
                            tone: AppNoticeTone.error,
                            message: _responsableError!,
                          ),
                        ],
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            FilledButton(
                              key: const ValueKey(
                                'actividad.guardar_responsable',
                              ),
                              onPressed:
                                  _loadingResponsables || _savingResponsable
                                  ? null
                                  : () => _saveResponsable(record),
                              child: Text(
                                _savingResponsable
                                    ? 'Guardando...'
                                    : 'Guardar responsable',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _savingResponsable
                                  ? null
                                  : () => setState(() {
                                      _editingResponsable = false;
                                      _responsableError = null;
                                    }),
                              child: const Text('Cancelar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 28),
              SectionTitle(
                _isLote
                    ? 'Información del lote'
                    : (_isCosecha
                          ? 'Información de la cosecha'
                          : 'Información de la actividad'),
                color: look.tone,
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: AppTheme.border, width: 1),
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
              if (_isCosecha && cosecha != null) ...[
                const SizedBox(height: 24),
                SectionTitle('Cantidades y equivalencias', color: look.tone),
                const SizedBox(height: 14),
                if (cosecha.formattedBaseKg != null ||
                    cosecha.equivalenciaLine != null)
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.border, width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (cosecha.formattedBaseKg != null)
                          DetailField(
                            label: 'Cantidad base (kg)',
                            value: cosecha.formattedBaseKg!,
                          ),
                        if (cosecha.cantidadEmpaques != null) ...[
                          const Divider(height: 1),
                          DetailField(
                            label: cosecha.empaqueLabel ?? 'Empaques',
                            value: '${cosecha.cantidadEmpaques}',
                          ),
                        ],
                        if (cosecha.cantidadUnidades != null) ...[
                          const Divider(height: 1),
                          DetailField(
                            label: 'Unidades estimadas',
                            value: '${cosecha.cantidadUnidades} unidades',
                          ),
                        ],
                        if (cosecha.equivalenciaLine != null) ...[
                          const Divider(height: 1),
                          DetailField(
                            label: 'Resumen de equivalencia',
                            value: cosecha.equivalenciaLine!,
                          ),
                        ],
                        if (cosecha.pesoPromedioKg != null) ...[
                          const Divider(height: 1),
                          DetailField(
                            label: 'Peso promedio por unidad',
                            value:
                                '${formatCosechaDecimal(cosecha.pesoPromedioKg!)} kg',
                          ),
                        ],
                        if (cosecha.conteoPorEmpaque != null) ...[
                          const Divider(height: 1),
                          DetailField(
                            label: 'Unidades por empaque',
                            value: '${cosecha.conteoPorEmpaque}',
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  const AppNotice(
                    tone: AppNoticeTone.info,
                    message: 'Sin equivalencias registradas para esta cosecha.',
                  ),
              ],
              if (!_isLote && actividad != null && actividad.isCompleted) ...[
                const SizedBox(height: 24),
                SectionTitle('Fotografía de evidencia', color: look.tone),
                const SizedBox(height: 14),
                _buildEvidenceSection(record, actividad),
              ],
              if (!_isLote &&
                  actividad != null &&
                  !actividad.isCompleted &&
                  actividad.plannedInsumos.isNotEmpty) ...[
                const SizedBox(height: 24),
                SectionTitle('Insumos asignados', color: look.tone),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.border, width: 1),
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
                        i < actividad.plannedInsumos.length;
                        i++
                      ) ...[
                        if (i > 0) const Divider(height: 1),
                        DetailField(
                          label: actividad.plannedInsumos[i].name,
                          value: actividad.plannedInsumos[i].formattedQuantity,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (!_isLote &&
                  actividad != null &&
                  (actividad.isCompleted || actividad.consumos.isNotEmpty)) ...[
                const SizedBox(height: 24),
                SectionTitle('Insumos utilizados', color: look.tone),
                const SizedBox(height: 14),
                if (actividad.consumos.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.border, width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < actividad.consumos.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          DetailField(
                            label: actividad.consumos[i].name,
                            value: actividad.consumos[i].formattedQuantity,
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  const AppNotice(
                    tone: AppNoticeTone.info,
                    message: 'Sin insumos registrados en esta actividad.',
                  ),
              ],
              if (!_isLote &&
                  actividad != null &&
                  actividad.loteId > 0 &&
                  AppModule.lotes.canOpen(widget.user)) ...[
                const SizedBox(height: 24),
                PressableCard(
                  key: const ValueKey('actividad.ver_historial_lote'),
                  onTap: () => _openLoteHistory(
                    actividad.loteId,
                    actividad.loteName ?? widget.returnToLoteName,
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
                              widget.returnToLoteId == actividad.loteId
                                  ? 'Volver al historial del lote'
                                  : 'Historial del lote',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              actividad.loteName ?? 'Lote #${actividad.loteId}',
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
              if (_isActividad &&
                  ActividadPermissions.canAddObservations(widget.user)) ...[
                const SizedBox(height: 20),
                if (_editingObservations)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.border, width: 1),
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

  Widget _buildEvidenceSection(
    ModuleRecord record,
    ActividadEditableData actividad,
  ) {
    if (actividad.isEvidenceUnavailable) {
      return const AppNotice(
        tone: AppNoticeTone.info,
        message:
            'Fotografía no disponible: el archivo registrado no está disponible en el servidor.',
      );
    }
    if (!actividad.isEvidenceAvailable) {
      return const AppNotice(
        tone: AppNoticeTone.info,
        message: 'Sin fotografía registrada para esta actividad.',
      );
    }
    final evidenceFuture = _ensureEvidenceRequest(record);
    return FutureBuilder<Uint8List>(
      future: evidenceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Cargando fotografía de evidencia...')),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final message = error is ApiException
              ? error.message
              : 'No se pudo cargar la fotografía de evidencia.';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppNotice(tone: AppNoticeTone.error, message: message),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('actividad.evidencia.reintentar'),
                  onPressed: () => _retryEvidence(record.id),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar carga'),
                ),
              ),
            ],
          );
        }
        final bytes = snapshot.requireData;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: const ValueKey('actividad.evidencia.imagen'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openEvidenceViewer(bytes, record.title),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    bytes,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 180,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined, size: 64),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('actividad.evidencia.ampliar'),
                  onPressed: () => _openEvidenceViewer(bytes, record.title),
                  icon: const Icon(Icons.zoom_in_rounded),
                  label: const Text('Ampliar fotografía'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
