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
import 'module_access_denied.dart';

class PlantaProcesamientoScreen extends StatefulWidget {
  const PlantaProcesamientoScreen({
    super.key,
    required this.loteProduccionId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final int loteProduccionId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<PlantaProcesamientoScreen> createState() =>
      _PlantaProcesamientoScreenState();
}

class _PlantaProcesamientoScreenState extends State<PlantaProcesamientoScreen> {
  ProcesamientoRecorrido? _recorrido;
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  @override
  void initState() {
    super.initState();
    if (PlantaPermissions.canViewProcesamiento(widget.user)) {
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
      final result = await widget.service.loadProcesamientoRecorrido(
        widget.user,
        widget.loteProduccionId,
      );
      if (!mounted) return;
      setState(() {
        _recorrido = result;
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
        _error = 'No se pudo consultar la ficha del procesamiento.';
      });
    }
  }

  void _back() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(AppModule.tareasPlanta.route);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlantaPermissions.canViewProcesamiento(widget.user) ||
        (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Ficha de procesamiento',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Origen y resultado'),
        actions: [
          IconButton(
            key: const ValueKey('procesamiento.actualizar'),
            tooltip: 'Actualizar ficha',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando ficha del procesamiento...')
            : _errorStatus == 404
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Procesamiento no disponible',
                message:
                    'No existe este lote de producción o tu cuenta no tiene acceso para consultarlo.',
              )
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _content(context, _recorrido!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          key: const ValueKey('procesamiento.volver'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ProcesamientoRecorrido recorrido) {
    final look = AppModule.tareasPlanta.look;
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
                      'Lote de producción #${recorrido.loteProduccionId}',
                      style: TextStyle(
                        color: look.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: Text(
                        recorrido.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (recorrido.codigo != null &&
                        recorrido.codigo != recorrido.title) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Código: ${recorrido.codigo}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle('Lotes de origen', color: look.tone),
              const SizedBox(height: 12),
              if (recorrido.origenes.isEmpty)
                const AppNotice(
                  tone: AppNoticeTone.info,
                  message:
                      'No hay lotes de origen visibles registrados para este procesamiento.',
                )
              else
                for (final origen in recorrido.origenes) ...[
                  _origenCard(context, origen),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 16),
              SectionTitle('Productos obtenidos', color: look.tone),
              const SizedBox(height: 12),
              if (recorrido.productosObtenidos.isEmpty)
                const AppNotice(
                  tone: AppNoticeTone.info,
                  message:
                      'Todavía no hay productos obtenidos visibles para este procesamiento.',
                )
              else
                for (final producto in recorrido.productosObtenidos) ...[
                  _productoCard(
                    context,
                    producto,
                    recorrido.ingresosProduccion
                        .where((i) => i.partidaId == producto.partidaId)
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _productoCard(
    BuildContext context,
    ProductoObtenidoProcesamiento producto,
    List<IngresoProduccionProcesamiento> ingresos,
  ) {
    return Container(
      key: ValueKey('procesamiento.producto.${producto.partidaId}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(producto.label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          DetailField(
            label: 'Partida obtenida',
            value: 'Partida #${producto.partidaId}',
          ),
          if (ingresos.isEmpty) ...[
            const Divider(height: 1),
            const DetailField(
              label: 'Cantidad producida',
              value: 'Cantidad original no conservada en este registro',
            ),
          ] else
            for (final ingreso in ingresos) ...[
              const Divider(height: 1),
              DetailField(
                label: 'Cantidad producida',
                value:
                    ingreso.formattedCantidad ??
                    'Cantidad original no conservada',
              ),
              if (ingreso.formattedKg != null) ...[
                const Divider(height: 1),
                DetailField(
                  label: 'Equivalente en kg',
                  value: ingreso.formattedKg!,
                ),
              ],
            ],
        ],
      ),
    );
  }

  Widget _origenCard(BuildContext context, OrigenProcesamiento origen) {
    return Container(
      key: ValueKey('procesamiento.origen.${origen.consumoId}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(origen.insumo, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          DetailField(label: 'Lote de origen', value: origen.loteOrigenLabel),
          if (origen.referenciaPartida != null) ...[
            const Divider(height: 1),
            DetailField(
              label: 'Partida / referencia',
              value: origen.referenciaPartida!,
            ),
          ],
          if (origen.presentacion != null) ...[
            const Divider(height: 1),
            DetailField(label: 'Presentación', value: origen.presentacion!),
          ],
          const Divider(height: 1),
          DetailField(
            label: 'Cantidad utilizada',
            value: origen.formattedConsumida,
          ),
          if (origen.formattedUnidadesConsumidas != null) ...[
            const Divider(height: 1),
            DetailField(
              label: 'Unidades consumidas',
              value: origen.formattedUnidadesConsumidas!,
            ),
          ],
          if (origen.formattedRecibida != null) ...[
            const Divider(height: 1),
            DetailField(
              label: 'Cantidad recibida en recepción',
              value: origen.formattedRecibida!,
            ),
          ],
        ],
      ),
    );
  }
}
