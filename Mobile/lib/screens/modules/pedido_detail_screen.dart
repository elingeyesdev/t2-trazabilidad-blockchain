import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/pedido_models.dart';
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

class PedidoDetailScreen extends StatefulWidget {
  const PedidoDetailScreen({
    super.key,
    required this.tipo,
    required this.pedidoId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final PedidoTipo tipo;
  final int pedidoId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<PedidoDetailScreen> createState() => _PedidoDetailScreenState();
}

class _PedidoDetailScreenState extends State<PedidoDetailScreen> {
  PedidoRecord? _record;
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  bool get _canView => widget.tipo == PedidoTipo.agricola
      ? PedidoPermissions.canViewAgricola(widget.user)
      : PedidoPermissions.canViewDistribucion(widget.user);

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
      final result = await widget.service.loadPedidoMovilDetail(
        widget.user,
        tipo: widget.tipo,
        id: widget.pedidoId,
      );
      if (!mounted) return;
      setState(() {
        _record = result;
        _loading = false;
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

  void _backToList() {
    final navigator = Navigator.of(context);
    final listRoute = AppModule.pedidos.route;
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
}
