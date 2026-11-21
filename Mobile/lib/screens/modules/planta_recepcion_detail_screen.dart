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

class PlantaRecepcionDetailScreen extends StatefulWidget {
  const PlantaRecepcionDetailScreen({
    super.key,
    required this.pedidoId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.onRecepcionUpdated,
  });

  final int pedidoId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final VoidCallback? onRecepcionUpdated;

  @override
  State<PlantaRecepcionDetailScreen> createState() =>
      _PlantaRecepcionDetailScreenState();
}

class _PlantaRecepcionDetailScreenState
    extends State<PlantaRecepcionDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<int, TextEditingController> _qtyControllers = {};

  RecepcionPlantaRecord? _record;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  int? _loadErrorStatus;
  ApiException? _submitError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    if (PlantaPermissions.canViewRecepciones(widget.user)) {
      unawaited(_load());
    } else {
      _loading = false;
      _loadErrorStatus = 403;
    }
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(RecepcionLinea line) =>
      _qtyControllers.putIfAbsent(
        line.detallePedidoId,
        () => TextEditingController(text: line.cantidadEnviada),
      );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _loadErrorStatus = null;
    });
    try {
      final record = await widget.service.loadRecepcionPlantaDetail(
        widget.user,
        widget.pedidoId,
      );
      if (!mounted) return;
      for (final line in record.lineas) {
        _controllerFor(line);
      }
      setState(() {
        _record = record;
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
        _loadError = 'No se pudo consultar el detalle de la recepción.';
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

  Future<void> _confirm(RecepcionPlantaRecord record) async {
    if (_submitting || record.isReceived) return;
    if (!validateForm(_formKey)) return;

    final cantidades = <String, String>{};
    final summary = <String>[
      'Solicitud: ${record.numeroSolicitud}',
      if (record.almacenId != null) 'Almacén destino: #${record.almacenId}',
    ];
    for (final line in record.lineas) {
      final raw = _controllerFor(line).text.trim().replaceAll(',', '.');
      cantidades['${line.detallePedidoId}'] = raw;
      final parsed = double.tryParse(raw) ?? 0;
      final discrepancy = parsed < line.enviadaValue - 1e-9
          ? ' (menor a ${line.formattedEnviada} enviados)'
          : '';
      summary.add(
        '${line.producto} (${line.origenLoteLabel}): $raw ${line.unidad} recibidos$discrepancy',
      );
    }

    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.move_to_inbox_rounded,
      title: '¿Confirmar recepción en planta?',
      message:
          'Se registrará el pesaje final de materia prima y se actualizará el inventario de planta.',
      details: summary,
      cancelLabel: 'Revisar datos',
      confirmLabel: 'Confirmar recepción',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await widget.service.confirmRecepcionPlanta(
        widget.user,
        pedidoId: record.pedidoId,
        cantidades: cantidades,
      );
      if (!mounted) return;
      widget.onRecepcionUpdated?.call();
      setState(() {
        _submitting = false;
        _notice =
            'Recepción de ${record.numeroSolicitud} confirmada correctamente.';
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
          'No se pudo registrar la recepción. Tus cantidades se conservaron para reintentar.',
        );
      });
    }
  }

  void _backToList() {
    final navigator = Navigator.of(context);
    final listRoute = AppModule.recepcionesPlanta.route;
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
    if (!PlantaPermissions.canViewRecepciones(widget.user) ||
        (!_loading && _loadErrorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Recepción en planta',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver a recepciones',
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Recepción de materia prima'),
        actions: [
          IconButton(
            tooltip: 'Actualizar recepción',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando recepción...')
            : _loadErrorStatus == 404
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'La recepción no está disponible',
                message: 'Vuelve al listado de recepciones para actualizar.',
              )
            : _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _load)
            : _content(context, _record!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a recepciones'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, RecepcionPlantaRecord record) {
    final look = AppModule.recepcionesPlanta.look;
    final canConfirm =
        !record.isReceived &&
        PlantaPermissions.canConfirmRecepcion(widget.user);
    final scrollPadding = formScrollPadding(context);
    final mappedFields = <String>{
      'cantidades',
      for (final line in record.lineas) 'cantidades.${line.detallePedidoId}',
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
    final cantidadesError = _fieldError('cantidades');

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
                    Text(
                      record.numeroSolicitud,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    RecordStatusBadge(status: record.estadoLabel),
                    if (record.fechaRecepcion != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Recibida el ${record.fechaRecepcion}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              if (_notice case final notice?) ...[
                const SizedBox(height: 18),
                AppNotice(tone: AppNoticeTone.success, message: notice),
              ],
              const SizedBox(height: 24),
              SectionTitle('Cantidades de materia prima', color: look.tone),
              const SizedBox(height: 12),
              if (canConfirm)
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in record.lineas) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radius,
                            ),
                            border: Border.all(color: AppTheme.ink, width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                line.producto,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Lote de origen: ${line.origenLoteLabel}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Enviado: ${line.formattedEnviada}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: ValueKey(
                                  'recepcion.cantidad.${line.detallePedidoId}',
                                ),
                                controller: _controllerFor(line),
                                scrollPadding: scrollPadding,
                                enabled: !_submitting,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                forceErrorText: _fieldError(
                                  'cantidades.${line.detallePedidoId}',
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Cantidad recibida',
                                  suffixText: line.unidad,
                                  prefixIcon: const Icon(Icons.scale_outlined),
                                ),
                                validator: (value) => validateRecepcionQuantity(
                                  value,
                                  maxEnviada: line.enviadaValue,
                                ),
                                onChanged: (_) {
                                  _clearError(
                                    field: 'cantidades.${line.detallePedidoId}',
                                  );
                                  _clearError(field: 'cantidades');
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (cantidadesError != null) ...[
                        AppNotice(
                          tone: AppNoticeTone.error,
                          message: cantidadesError,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (generalError != null) ...[
                        AppNotice(
                          tone: AppNoticeTone.error,
                          message: generalError,
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: const ValueKey('recepcion.confirmar'),
                        onPressed: _submitting ? null : () => _confirm(record),
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.move_to_inbox_rounded),
                        label: Text(
                          _submitting
                              ? 'Registrando recepción...'
                              : 'Registrar recepción',
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final line in record.lineas) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.ink, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          line.producto,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        DetailField(
                          label: 'Lote de origen',
                          value: line.origenLoteLabel,
                        ),
                        const Divider(height: 1),
                        DetailField(
                          label: 'Cantidad enviada',
                          value: line.formattedEnviada,
                        ),
                        if (line.formattedRecibida != null) ...[
                          const Divider(height: 1),
                          DetailField(
                            label: 'Cantidad recibida',
                            value: line.formattedRecibida!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
