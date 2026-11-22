import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/entrega_models.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

class EntregaDetailScreen extends StatefulWidget {
  const EntregaDetailScreen({
    super.key,
    required this.rutaId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.onEntregaUpdated,
  });

  final int rutaId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final VoidCallback? onEntregaUpdated;

  @override
  State<EntregaDetailScreen> createState() => _EntregaDetailScreenState();
}

class _EntregaDetailScreenState extends State<EntregaDetailScreen> {
  RutaEntregaRecord? _ruta;
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  @override
  void initState() {
    super.initState();
    if (EntregaPermissions.canViewRutas(widget.user)) {
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
      final result = await widget.service.loadRutaEntregaDetail(
        widget.user,
        widget.rutaId,
      );
      if (!mounted) return;
      setState(() {
        _ruta = result;
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
        _error = 'No se pudo consultar el detalle de la entrega.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!EntregaPermissions.canViewRutas(widget.user) ||
        (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Detalle de entrega',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de entrega'),
        actions: [
          IconButton(
            key: const ValueKey('entrega.actualizar'),
            tooltip: 'Actualizar entrega',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando detalle de la entrega...')
            : _errorStatus == 404
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Entrega no disponible',
                message:
                    'La ruta de entrega no existe o tu cuenta no tiene acceso.',
              )
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _content(context, _ruta!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          key: const ValueKey('entrega.volver'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a envíos'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, RutaEntregaRecord ruta) {
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
                    color: AppTheme.sprout,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppTheme.ink, width: 2),
                    boxShadow: AppTheme.stamp(5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ruta #${ruta.id}',
                        style: const TextStyle(
                          color: AppTheme.forest,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ruta.nombre,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      RecordStatusBadge(
                        key: const ValueKey('entrega.estado_badge'),
                        status: ruta.estadoLabel,
                      ),
                      if (ruta.fechaSalida != null) ...[
                        const SizedBox(height: 8),
                        Text('Salida: ${ruta.fechaSalida}'),
                      ],
                      if (ruta.fechaCierre != null) ...[
                        const SizedBox(height: 4),
                        Text('Cierre: ${ruta.fechaCierre}'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionTitle('Paradas en orden'),
                const SizedBox(height: 12),
                if (ruta.paradas.isEmpty)
                  const AppNotice(
                    tone: AppNoticeTone.info,
                    message: 'Esta ruta todavía no tiene paradas registradas.',
                  )
                else
                  for (final parada in ruta.paradas) ...[
                    _paradaCard(context, parada),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paradaCard(BuildContext context, ParadaEntrega parada) {
    return Container(
      key: ValueKey('entrega.parada.${parada.orden}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Parada #${parada.orden}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              RecordStatusBadge(status: parada.estadoLabel),
            ],
          ),
          const SizedBox(height: 10),
          DetailField(label: 'Destino', value: parada.destinoLabel),
          if (parada.direccion != null &&
              parada.direccion != parada.destinoLabel) ...[
            const Divider(height: 1),
            DetailField(label: 'Dirección', value: parada.direccion!),
          ],
          if (parada.externoEnvioId != null) ...[
            const Divider(height: 1),
            DetailField(label: 'Envío', value: parada.externoEnvioId!),
          ],
        ],
      ),
    );
  }
}
