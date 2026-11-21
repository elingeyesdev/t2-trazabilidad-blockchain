import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/planta_models.dart';
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
import 'module_access_denied.dart';

class PlantaTareaDetailScreen extends StatefulWidget {
  const PlantaTareaDetailScreen({
    super.key,
    required this.asignacionId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.onTareaUpdated,
  });

  final int asignacionId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final VoidCallback? onTareaUpdated;

  @override
  State<PlantaTareaDetailScreen> createState() =>
      _PlantaTareaDetailScreenState();
}

class _PlantaTareaDetailScreenState extends State<PlantaTareaDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<int, TextEditingController> _paramControllers = {};

  TareaPlantaDetail? _detail;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  int? _loadErrorStatus;
  ApiException? _submitError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    if (PlantaPermissions.canViewTareas(widget.user)) {
      unawaited(_load());
    } else {
      _loading = false;
      _loadErrorStatus = 403;
    }
  }

  @override
  void dispose() {
    for (final controller in _paramControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int variableId) =>
      _paramControllers.putIfAbsent(variableId, () => TextEditingController());

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _loadErrorStatus = null;
    });
    try {
      final detail = await widget.service.loadTareaPlantaDetail(
        widget.user,
        widget.asignacionId,
      );
      if (!mounted) return;
      for (final param in detail.parametrosRequeridos) {
        _controllerFor(param.variableEstandarId);
      }
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.message;
        _loadErrorStatus = error.statusCode;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'No se pudo consultar el detalle de la tarea de planta.';
      });
    }
  }

  String? _fieldError(String field) {
    final messages = _submitError?.validationErrors[field];
    return messages == null || messages.isEmpty ? null : messages.join('\n');
  }

  void _clearError({String? field}) {
    final error = _submitError;
    if (error == null) return;
    if (field != null && error.validationErrors.isNotEmpty) {
      if (!error.validationErrors.containsKey(field)) return;
      final remaining = Map.of(error.validationErrors)..remove(field);
      setState(() {
        _submitError = remaining.isEmpty
            ? null
            : ApiException(
                error.message,
                statusCode: error.statusCode,
                validationErrors: remaining,
              );
      });
    } else {
      setState(() => _submitError = null);
    }
  }

  Future<void> _completeStage(TareaPlantaDetail detail) async {
    if (_submitting || !detail.puedeCompletar) return;
    if (!validateForm(_formKey)) return;

    final parametros = <Map<String, Object?>>[];
    final summaryLines = <String>[
      'Lote de resultado: ${detail.tarea.loteLabel}',
      'Proceso: ${detail.tarea.procesoNombre} (Etapa ${detail.tarea.orden})',
      'Máquina: ${detail.tarea.maquinaLabel}',
    ];
    for (final param in detail.parametrosRequeridos) {
      final raw = _controllerFor(
        param.variableEstandarId,
      ).text.trim().replaceAll(',', '.');
      parametros.add({
        'variableestandarid': param.variableEstandarId,
        'valor': raw,
      });
      final unit = param.unidad == null || param.unidad!.isEmpty
          ? ''
          : ' ${param.unidad}';
      summaryLines.add('${param.nombre}: $raw$unit');
    }

    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.task_alt_rounded,
      title: '¿Completar etapa de planta?',
      message:
          'Los resultados quedarán registrados y el proceso avanzará según el orden configurado.',
      details: summaryLines,
      confirmLabel: 'Confirmar cierre',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await widget.service.completeTareaPlanta(
        widget.user,
        loteProduccionId: detail.tarea.loteProduccionId,
        asignacionId: detail.tarea.id,
        parametros: parametros,
      );
      if (!mounted) return;
      widget.onTareaUpdated?.call();
      setState(() {
        _submitting = false;
        _notice =
            'Etapa ${detail.tarea.orden} (${detail.tarea.procesoNombre}) completada correctamente.';
      });
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error;
      });
      revealFormErrors(_formKey);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = const ApiException(
          'No se pudieron guardar los resultados. Tus datos se conservaron para reintentar.',
        );
      });
    }
  }

  void _backToList() {
    final navigator = Navigator.of(context);
    final listRoute = AppModule.tareasPlanta.route;
    var found = false;
    navigator.popUntil((route) {
      found = route.settings.name == listRoute;
      return found || route.isFirst;
    });
    if (!found) {
      navigator.pushNamed(listRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlantaPermissions.canViewTareas(widget.user) ||
        (!_loading && _loadErrorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Detalle de tarea de planta',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver a tareas de planta',
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Detalle de tarea'),
        actions: [
          IconButton(
            tooltip: 'Actualizar tarea',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando detalle de la etapa...')
            : _loadErrorStatus == 404
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'La tarea ya no está disponible',
                message:
                    'Vuelve a la lista de tareas de planta para actualizar.',
              )
            : _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _load)
            : _content(context, _detail!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a tareas de planta'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, TareaPlantaDetail detail) {
    final look = AppModule.tareasPlanta.look;
    final tarea = detail.tarea;
    final machineStatus = tarea.maquinaActiva
        ? 'Disponible'
        : 'En mantenimiento';

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
                        ModuleMark(
                          AppModule.tareasPlanta,
                          size: 48,
                          solid: true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Etapa ${tarea.orden} · Tarea #${tarea.id}',
                            style: TextStyle(
                              color: look.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      header: true,
                      child: Text(
                        tarea.procesoNombre,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RecordStatusBadge(status: tarea.estadoLabel),
                  ],
                ),
              ),
              if (_notice case final notice?) ...[
                const SizedBox(height: 18),
                AppNotice(tone: AppNoticeTone.success, message: notice),
              ],
              const SizedBox(height: 24),
              SectionTitle('Proceso y etapa', color: look.tone),
              const SizedBox(height: 12),
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
                    DetailField(label: 'Proceso', value: tarea.procesoNombre),
                    const Divider(height: 1),
                    DetailField(
                      label: 'Etapa del proceso',
                      value: 'Etapa ${tarea.orden}',
                    ),
                    const Divider(height: 1),
                    DetailField(
                      label: 'Lote de producción',
                      value: tarea.loteLabel,
                    ),
                    if (tarea.loteProducto != null) ...[
                      const Divider(height: 1),
                      DetailField(
                        label: 'Producto',
                        value: tarea.loteProducto!,
                      ),
                    ],
                    if (tarea.completadaEn != null) ...[
                      const Divider(height: 1),
                      DetailField(
                        label: 'Completada el',
                        value: tarea.completadaEn!,
                      ),
                    ],
                    if (tarea.observaciones != null) ...[
                      const Divider(height: 1),
                      DetailField(
                        label: 'Observaciones',
                        value: tarea.observaciones!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle('Máquina asignada', color: look.tone),
              const SizedBox(height: 12),
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
                    DetailField(label: 'Máquina', value: tarea.maquinaNombre),
                    if (tarea.maquinaCodigo != null) ...[
                      const Divider(height: 1),
                      DetailField(
                        label: 'Código de máquina',
                        value: tarea.maquinaCodigo!,
                      ),
                    ],
                    const Divider(height: 1),
                    DetailField(
                      label: 'Estado de máquina',
                      value: machineStatus,
                    ),
                  ],
                ),
              ),
              if (detail.puedeCompletar) ...[
                const SizedBox(height: 24),
                SectionTitle(
                  'Registrar resultados de la etapa',
                  color: look.tone,
                ),
                const SizedBox(height: 12),
                _completionForm(context, detail),
              ] else if (!tarea.isCompleted) ...[
                const SizedBox(height: 24),
                SectionTitle(
                  tarea.isCancelled
                      ? 'Estado de la etapa'
                      : 'Requisito pendiente',
                  color: AppTheme.maize,
                ),
                const SizedBox(height: 12),
                _prerequisiteNotice(context, detail),
              ],
              if (detail.resultadoParametros.isNotEmpty) ...[
                const SizedBox(height: 24),
                SectionTitle('Resultados registrados', color: look.tone),
                const SizedBox(height: 12),
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
                      DetailField(
                        label: 'Lote de resultado',
                        value: tarea.loteLabel,
                      ),
                      for (
                        var i = 0;
                        i < detail.resultadoParametros.length;
                        i++
                      ) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: detail.resultadoParametros[i].nombre,
                          value: detail.resultadoParametros[i].formattedValue,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _prerequisiteNotice(BuildContext context, TareaPlantaDetail detail) {
    final tarea = detail.tarea;
    final reason = tarea.isCancelled
        ? 'Esta tarea fue cancelada y no permite registrar resultados.'
        : (detail.requisitoPendiente ??
              (!tarea.maquinaActiva
                  ? 'La máquina asignada (${tarea.maquinaLabel}) se encuentra en mantenimiento.'
                  : 'Debes completar la etapa anterior del proceso antes de continuar con esta etapa.'));
    return Container(
      key: const ValueKey('planta.tarea.requisito'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.maizeSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: const Color(0xFF8A5E00), width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tarea.isCancelled
                ? Icons.cancel_outlined
                : Icons.lock_clock_rounded,
            color: const Color(0xFF5F4100),
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tarea.isCancelled
                      ? 'Etapa cancelada'
                      : 'No se puede completar todavía',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF5F4100),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppTheme.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _completionForm(BuildContext context, TareaPlantaDetail detail) {
    final scrollPadding = formScrollPadding(context);
    final mappedFields = <String>{
      'parametros',
      for (var i = 0; i < detail.parametrosRequeridos.length; i++) ...[
        'parametros.$i.valor',
        'parametros.$i.variableestandarid',
      ],
    };
    final error = _submitError;
    final generalError =
        error != null &&
            (error.validationErrors.isEmpty ||
                error.validationErrors.keys.any(
                  (field) => !mappedFields.contains(field),
                ))
        ? error.message
        : null;
    final paramsError = _fieldError('parametros');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lote de resultado: ${detail.tarea.loteLabel}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (detail.parametrosRequeridos.isEmpty)
              const Text(
                'Esta etapa no requiere mediciones adicionales. Puedes confirmar su cierre directamente.',
              )
            else ...[
              const Text(
                'Introduce las mediciones reales registradas en esta etapa antes de completar.',
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < detail.parametrosRequeridos.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _paramField(
                  detail.parametrosRequeridos[i],
                  index: i,
                  scrollPadding: scrollPadding,
                ),
              ],
            ],
            if (paramsError != null) ...[
              const SizedBox(height: 14),
              AppNotice(tone: AppNoticeTone.error, message: paramsError),
            ],
            if (generalError != null) ...[
              const SizedBox(height: 14),
              AppNotice(tone: AppNoticeTone.error, message: generalError),
              if (error?.statusCode == 409 || error?.statusCode == 403) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('planta.tarea.recargar_tras_rechazo'),
                    onPressed: _submitting ? null : _load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Actualizar estado de la tarea'),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('planta.tarea.completar'),
              onPressed: _submitting ? null : () => _completeStage(detail),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt_rounded),
              label: Text(
                _submitting ? 'Guardando resultados...' : 'Completar etapa',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paramField(
    ParametroRequerido param, {
    required int index,
    required EdgeInsets scrollPadding,
  }) {
    final fieldKey = 'parametros.$index.valor';
    return TextFormField(
      key: ValueKey('planta.param.${param.variableEstandarId}'),
      controller: _controllerFor(param.variableEstandarId),
      scrollPadding: scrollPadding,
      enabled: !_submitting,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      forceErrorText:
          _fieldError(fieldKey) ??
          _fieldError('parametros.$index.variableestandarid'),
      decoration: InputDecoration(
        labelText: param.nombre,
        suffixText: param.unidad,
        helperText: param.rangeHint,
        prefixIcon: const Icon(Icons.tune_rounded),
      ),
      validator: (value) {
        final normalized = (value ?? '').trim().replaceAll(',', '.');
        if (normalized.isEmpty) {
          return 'Registra el valor medido de ${param.nombre}.';
        }
        final parsed = double.tryParse(normalized);
        if (parsed == null || !parsed.isFinite) {
          return 'Indica un número válido.';
        }
        if (param.valorMinimo != null && parsed < param.valorMinimo!) {
          return 'El valor está por debajo del mínimo (${param.rangeHint ?? param.valorMinimo}).';
        }
        if (param.valorMaximo != null && parsed > param.valorMaximo!) {
          return 'El valor supera el máximo (${param.rangeHint ?? param.valorMaximo}).';
        }
        return null;
      },
      onChanged: (_) {
        _clearError(field: fieldKey);
        _clearError(field: 'parametros');
      },
    );
  }
}
