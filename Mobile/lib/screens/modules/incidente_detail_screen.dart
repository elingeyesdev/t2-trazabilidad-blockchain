import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/incidente_models.dart';
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

class IncidenteDetailScreen extends StatefulWidget {
  const IncidenteDetailScreen({
    super.key,
    required this.incidenteId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.onIncidenteUpdated,
  });

  final int incidenteId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final VoidCallback? onIncidenteUpdated;

  @override
  State<IncidenteDetailScreen> createState() => _IncidenteDetailScreenState();
}

class _IncidenteDetailScreenState extends State<IncidenteDetailScreen> {
  IncidenteRecord? _record;
  bool _loading = true;
  bool _resolving = false;
  String? _error;
  int? _errorStatus;
  String? _actionError;
  String? _notice;

  bool get _canView => IncidentePermissions.canView(widget.user);

  @override
  void initState() {
    super.initState();
    if (_canView) {
      unawaited(_load());
    } else {
      _loading = false;
      _errorStatus = 403;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = null;
    });
    try {
      final result = await widget.service.loadIncidenteDetail(
        widget.user,
        widget.incidenteId,
      );
      if (!mounted) return;
      setState(() {
        _record = result;
        _loading = false;
        _actionError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
        _errorStatus = error.statusCode;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo consultar el detalle de la incidencia.';
      });
    }
  }

  bool _canResolveRecord(IncidenteRecord record) {
    if (record.isResolved) return false;
    if (!IncidentePermissions.canResolve(widget.user)) return false;
    return record.puedeResolver != false;
  }

  Future<void> _openResolveDialog(IncidenteRecord record) async {
    if (_resolving) return;
    final nota = await showDialog<String>(
      context: context,
      builder: (_) => _ResolveIncidenteDialog(record: record),
    );
    if (!mounted || nota == null || nota.trim().isEmpty) return;

    setState(() {
      _resolving = true;
      _actionError = null;
      _notice = null;
    });

    try {
      final updated = await widget.service.resolveIncidente(
        widget.user,
        record.id,
        notaResolucion: nota,
      );
      if (!mounted) return;
      widget.onIncidenteUpdated?.call();
      setState(() {
        _record = updated;
        _resolving = false;
        _notice = 'Incidencia #${updated.id} marcada como resuelta.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _actionError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _actionError =
            'No se pudo resolver la incidencia por un error de conexión.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView || (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Detalle de incidencia',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de incidencia'),
        actions: [
          IconButton(
            key: const ValueKey('incidente.actualizar'),
            tooltip: 'Actualizar incidencia',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando incidencia...')
            : _errorStatus == 404
            ? const AppEmptyState(
                icon: Icons.report_off_outlined,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Incidencia no encontrada',
                message:
                    'No encontramos el registro de incidencia solicitado o no pertenece a tu ámbito.',
              )
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _buildContent(context, _record!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a incidencias'),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, IncidenteRecord record) {
    final theme = Theme.of(context);
    final look = AppModule.incidentes.look;
    final canResolve = _canResolveRecord(record);

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_notice != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.sprout,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.sproutBorder),
                    ),
                    child: Text(
                      _notice!,
                      style: const TextStyle(
                        color: AppTheme.fieldDeep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_actionError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.claySoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.clay),
                    ),
                    child: Text(
                      _actionError!,
                      style: const TextStyle(
                        color: AppTheme.clay,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: look.tone,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.report_problem_outlined,
                              color: look.ink,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.tipo,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Incidencia #${record.id}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          RecordStatusBadge(status: record.seguimiento),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Descripción',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.descripcion,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const Divider(height: 24),
                      if (record.afectadoReferencia != null)
                        _metaRow(
                          context,
                          'Referencia afectada',
                          record.afectadoReferencia!,
                        ),
                      if (record.reportadoPorNombre != null)
                        _metaRow(
                          context,
                          'Reportado por',
                          record.reportadoPorNombre!,
                        ),
                      if (record.responsableNombre != null)
                        _metaRow(
                          context,
                          'Responsable asignado',
                          record.responsableNombre!,
                        ),
                      if (record.createdAt != null)
                        _metaRow(
                          context,
                          'Fecha de reporte',
                          record.createdAt!,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (record.isResolved)
                  Container(
                    key: const ValueKey('incidente.solucion_card'),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.sprout,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.sproutBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              color: AppTheme.fieldDeep,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Solución registrada',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: AppTheme.fieldDeep,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        if (record.notaResolucion != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            record.notaResolucion!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppTheme.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (record.resueltoPorNombre != null ||
                            record.fechaResolucion != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (record.resueltoPorNombre != null)
                                'Resuelto por: ${record.resueltoPorNombre}',
                              if (record.fechaResolucion != null)
                                'Fecha: ${record.fechaResolucion}',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.fieldDeep,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else if (canResolve)
                  FilledButton.icon(
                    key: const ValueKey('incidente.resolver'),
                    onPressed: _resolving
                        ? null
                        : () => _openResolveDialog(record),
                    icon: const Icon(Icons.task_alt_rounded),
                    label: Text(
                      _resolving ? 'Resolviendo...' : 'Resolver incidencia',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.inkSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolveIncidenteDialog extends StatefulWidget {
  const _ResolveIncidenteDialog({required this.record});

  final IncidenteRecord record;

  @override
  State<_ResolveIncidenteDialog> createState() =>
      _ResolveIncidenteDialogState();
}

class _ResolveIncidenteDialogState extends State<_ResolveIncidenteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notaCtrl = TextEditingController();

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_notaCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resolver incidencia'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Describe la solución aplicada para cerrar la incidencia #${widget.record.id}.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('incidente.nota_resolucion'),
                controller: _notaCtrl,
                maxLines: 4,
                maxLength: 2000,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nota de resolución',
                  hintText:
                      'Ej. Se repuso el lote dañado y se confirmó entrega',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa una explicación de la solución aplicada.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('incidente.confirmar_resolucion'),
          onPressed: _confirm,
          child: const Text('Confirmar solución'),
        ),
      ],
    );
  }
}
