import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/pedido_models.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

class PedidoDetailScreen extends StatefulWidget {
  const PedidoDetailScreen({
    super.key,
    required this.tipo,
    required this.pedidoId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.updates,
    this.onPedidoUpdated,
  });

  final PedidoTipo tipo;
  final int pedidoId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final ValueListenable<int>? updates;
  final VoidCallback? onPedidoUpdated;

  @override
  State<PedidoDetailScreen> createState() => _PedidoDetailScreenState();
}

class _PedidoDetailScreenState extends State<PedidoDetailScreen> {
  PedidoRecord? _record;
  bool _loading = true;
  bool _acting = false;
  String? _error;
  int? _errorStatus;
  String? _actionError;
  String? _notice;

  bool get _canView => widget.tipo == PedidoTipo.agricola
      ? PedidoPermissions.canViewAgricola(widget.user)
      : PedidoPermissions.canViewDistribucion(widget.user);

  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(_onExternalUpdate);
    if (_canView) {
      unawaited(_load());
    } else {
      _loading = false;
      _errorStatus = 403;
    }
  }

  @override
  void didUpdateWidget(covariant PedidoDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      oldWidget.updates?.removeListener(_onExternalUpdate);
      widget.updates?.addListener(_onExternalUpdate);
    }
  }

  @override
  void dispose() {
    widget.updates?.removeListener(_onExternalUpdate);
    super.dispose();
  }

  void _onExternalUpdate() {
    if (!mounted || !_canView) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = null;
    });
    try {
      final result = await widget.service.loadPedidoMovilDetail(
        widget.user,
        tipo: widget.tipo,
        id: widget.pedidoId,
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
        _error = 'No se pudo consultar el detalle del pedido.';
      });
    }
  }

  Future<void> _promptReject(PedidoRecord record) async {
    if (_acting) return;
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RejectPedidoDialog(numeroSolicitud: record.numeroSolicitud),
    );
    if (!mounted || motivo == null || motivo.isEmpty) return;
    await _executeAction(record, 'rechazar', motivoRechazo: motivo);
  }

  Future<void> _executeAction(
    PedidoRecord record,
    String accion, {
    String? motivoRechazo,
  }) async {
    if (_acting) return;
    if (accion != 'rechazar') {
      final label = pedidoAccionLabel(accion);
      final confirmed = await confirmImportantAction(
        context,
        icon: Icons.check_circle_outline_rounded,
        title: '¿$label?',
        message: 'Se registrará tu decisión oficial sobre este pedido.',
        details: [
          'Pedido: ${record.numeroSolicitud}',
          'Destino: ${record.destino.label}',
          'Estado actual: ${record.estadoLabel}',
        ],
        cancelLabel: 'Cancelar',
        confirmLabel: label,
      );
      if (!mounted || !confirmed) return;
    }

    setState(() {
      _acting = true;
      _actionError = null;
      _notice = null;
    });
    try {
      final updated = await widget.service.executePedidoTransicion(
        widget.user,
        tipo: record.tipo,
        pedidoId: record.id,
        accion: accion,
        motivoRechazo: motivoRechazo,
      );
      if (!mounted) return;
      widget.onPedidoUpdated?.call();
      setState(() {
        _record = updated;
        _acting = false;
        _notice = 'Decisión registrada: estado ${updated.estadoLabel}.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      final motivoErr = error.validationErrors['motivo_rechazo'];
      final detallesErr = error.validationErrors['detalles'];
      final message = (motivoErr != null && motivoErr.isNotEmpty)
          ? motivoErr.join('\n')
          : (detallesErr != null && detallesErr.isNotEmpty)
          ? detallesErr.join('\n')
          : error.message;
      setState(() {
        _acting = false;
        _actionError = message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _actionError =
            'No se pudo registrar la decisión por un error de conexión.';
      });
    }
  }

  void _backToList() {
    final navigator = Navigator.of(context);
    final gestionRoute = '${AppModule.pedidos.route}/gestion';
    final listRoute = AppModule.pedidos.route;
    var found = false;
    navigator.popUntil((route) {
      found =
          route.settings.name == gestionRoute ||
          route.settings.name == listRoute;
      return found || route.isFirst;
    });
    if (!found) {
      navigator.pushNamed(listRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView || (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Detalle de pedido',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver a pedidos',
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('Pedido ${widget.tipo.label.toLowerCase()}'),
        actions: [
          IconButton(
            key: const ValueKey('pedido.actualizar'),
            tooltip: 'Actualizar pedido',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando pedido...')
            : _errorStatus == 404
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Pedido no disponible',
                message:
                    'El pedido no existe o tu cuenta no tiene acceso para consultarlo.',
              )
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _content(context, _record!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          key: const ValueKey('pedido.volver'),
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a pedidos'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, PedidoRecord record) {
    final look = AppModule.pedidos.look;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                        'Pedido ${record.tipo.label}',
                        style: TextStyle(
                          color: look.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        record.numeroSolicitud,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      RecordStatusBadge(status: record.estadoLabel),
                    ],
                  ),
                ),
                if (_notice case final notice?) ...[
                  const SizedBox(height: 16),
                  AppNotice(tone: AppNoticeTone.success, message: notice),
                ],
                if (_actionError case final actionError?) ...[
                  const SizedBox(height: 16),
                  AppNotice(
                    key: const ValueKey('pedido.accion_error'),
                    tone: AppNoticeTone.error,
                    message: actionError,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('pedido.recargar_tras_error'),
                      onPressed: _loading || _acting ? null : _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Actualizar estado del pedido'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SectionTitle('Destino y resumen', color: look.tone),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.ink, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DetailField(
                        label: 'Destino',
                        value: record.destino.label,
                      ),
                      if (record.fechaEntregaDeseada != null) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: 'Entrega deseada',
                          value: record.fechaEntregaDeseada!,
                        ),
                      ],
                      if (record.observaciones != null) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: 'Observaciones',
                          value: record.observaciones!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SectionTitle('Estado e historial del pedido', color: look.tone),
                const SizedBox(height: 12),
                _historialCard(context, record),
                const SizedBox(height: 24),
                SectionTitle('Acciones disponibles', color: look.tone),
                const SizedBox(height: 12),
                _accionesCard(context, record),
                const SizedBox(height: 24),
                SectionTitle('Productos solicitados', color: look.tone),
                const SizedBox(height: 12),
                for (final line in record.detalles) ...[
                  Container(
                    key: ValueKey('pedido.detalle.${line.id}'),
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
                          line.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        DetailField(
                          label: 'Cantidad',
                          value: line.formattedCantidad,
                        ),
                        if (line.formattedKg != null &&
                            line.unidad != 'kg') ...[
                          const Divider(height: 1),
                          DetailField(
                            label: 'Equivalente en kg',
                            value: line.formattedKg!,
                          ),
                        ],
                        if (line.almacenOrigenId != null) ...[
                          const Divider(height: 1),
                          DetailField(
                            label: 'Almacén origen',
                            value: 'Almacén #${line.almacenOrigenId}',
                          ),
                        ],
                        if ((line.inventarioPresentacionLoteId ??
                                line.materiaPrimaLoteId)
                            case final partidaId?) ...[
                          const Divider(height: 1),
                          DetailField(
                            label: 'Partida',
                            value: 'Partida #$partidaId',
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
      ),
    );
  }

  Widget _historialCard(BuildContext context, PedidoRecord record) {
    final entries = <(String, String)>[
      ('Estado actual', record.estadoLabel),
      if (record.fecha != null) ('Fecha de solicitud', record.fecha!),
      if (record.fechaAceptacion != null)
        ('Fecha de aceptación', record.fechaAceptacion!),
      if (record.envioIniciadoMayorista == true)
        ('Modalidad', 'Envío iniciado por mayorista'),
      if (record.fechaConfirmacionMinorista != null)
        ('Confirmación del minorista', record.fechaConfirmacionMinorista!),
      if (record.fechaEnvio != null) ('Fecha de envío', record.fechaEnvio!),
      if (record.fechaRecepcion != null)
        ('Fecha de recepción', record.fechaRecepcion!),
      if (record.envio != null)
        (
          'Estado del envío agrícola',
          'Envío #${record.envio!.id}${record.envio!.estado != null ? ' · ${record.envio!.estado}' : ''}',
        ),
      if (record.envio?.fechaRecepcionPlanta != null)
        ('Recepción en planta', record.envio!.fechaRecepcionPlanta!),
      if (record.decision?.accion != null)
        (
          'Última decisión',
          '${pedidoAccionLabel(record.decision!.accion!)}${record.decision!.fecha != null ? ' (${record.decision!.fecha})' : ''}',
        ),
      if ((record.motivoRechazo ?? record.decision?.motivo) case final motivo?)
        ('Motivo registrado', motivo),
    ];

    return Container(
      key: const ValueKey('pedido.historial'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            DetailField(label: entries[i].$1, value: entries[i].$2),
          ],
        ],
      ),
    );
  }

  Widget _accionesCard(BuildContext context, PedidoRecord record) {
    final canUpdate =
        !widget.user.roles.contains('admin') &&
        (record.tipo == PedidoTipo.agricola
            ? widget.user.permissions.contains('pedidos.update')
            : widget.user.permissions.contains('pedidos_distribucion.update'));
    final acciones = canUpdate ? record.accionesDisponibles : const <String>[];

    if (acciones.isEmpty) {
      return const AppNotice(
        key: ValueKey('pedido.sin_acciones'),
        tone: AppNoticeTone.info,
        message:
            'No hay acciones disponibles para este pedido en su estado actual o con los permisos de tu cuenta.',
      );
    }

    return Container(
      key: const ValueKey('pedido.acciones'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final accion in acciones)
            if (accion == 'rechazar')
              OutlinedButton.icon(
                key: ValueKey('pedido.accion.$accion'),
                onPressed: _acting ? null : () => _promptReject(record),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: Text(pedidoAccionLabel(accion)),
              )
            else
              FilledButton.icon(
                key: ValueKey('pedido.accion.$accion'),
                onPressed: _acting
                    ? null
                    : () => _executeAction(record, accion),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(pedidoAccionLabel(accion)),
              ),
        ],
      ),
    );
  }
}

class _RejectPedidoDialog extends StatefulWidget {
  const _RejectPedidoDialog({required this.numeroSolicitud});

  final String numeroSolicitud;

  @override
  State<_RejectPedidoDialog> createState() => _RejectPedidoDialogState();
}

class _RejectPedidoDialogState extends State<_RejectPedidoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rechazar pedido'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Indica el motivo obligatorio para rechazar ${widget.numeroSolicitud}.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('pedido.motivo_rechazo_input'),
              controller: _controller,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Motivo de rechazo'),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) {
                  return 'Indica el motivo del rechazo.';
                }
                if (text.length > 500) {
                  return 'El motivo no puede superar 500 caracteres.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('pedido.confirmar_rechazo'),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_controller.text.trim());
          },
          child: const Text('Confirmar rechazo'),
        ),
      ],
    );
  }
}
