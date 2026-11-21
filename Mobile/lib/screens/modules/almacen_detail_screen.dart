import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/inventario_models.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import 'inventario_movimiento_form_screen.dart';
import 'module_access_denied.dart';

class AlmacenDetailScreen extends StatefulWidget {
  const AlmacenDetailScreen({
    super.key,
    required this.almacenId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.almacenName,
  });

  final int almacenId;
  final String? almacenName;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<AlmacenDetailScreen> createState() => _AlmacenDetailScreenState();
}

class _AlmacenDetailScreenState extends State<AlmacenDetailScreen> {
  AlmacenExistenciasPage? _existencias;
  InventarioMovimientosPage? _movimientos;
  bool _loading = true;
  bool _loadingMovimientos = false;
  String? _loadError;
  int? _loadErrorStatus;
  String? _movimientosError;
  String? _naturalezaFilter;
  String? _notice;

  String get _almacenTitle =>
      widget.almacenName ?? 'Almacén #${widget.almacenId}';

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _loadErrorStatus = null;
      _movimientosError = null;
    });
    try {
      final existencias = await widget.service.loadAlmacenExistencias(
        widget.user,
        widget.almacenId,
      );
      if (!mounted) return;
      setState(() {
        _existencias = existencias;
        _loading = false;
      });
      if (InventarioPermissions.canViewMovimientos(widget.user)) {
        await _loadMovimientos();
      }
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
        _loadError = 'No se pudieron consultar las existencias del almacén.';
      });
    }
  }

  Future<void> _loadMovimientos() async {
    if (!InventarioPermissions.canViewMovimientos(widget.user)) return;
    setState(() {
      _loadingMovimientos = true;
      _movimientosError = null;
    });
    try {
      final page = await widget.service.loadAlmacenMovimientos(
        widget.user,
        widget.almacenId,
        naturaleza: _naturalezaFilter,
      );
      if (!mounted) return;
      setState(() {
        _movimientos = page;
        _loadingMovimientos = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMovimientos = false;
        _movimientosError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMovimientos = false;
        _movimientosError =
            'No se pudo cargar el historial de movimientos del almacén.';
      });
    }
  }

  Future<void> _openMovimientoForm(
    MovimientoFormMode mode, {
    int? insumoId,
  }) async {
    final items = _existencias?.items ?? const [];
    if (items.isEmpty) return;
    final result = await Navigator.of(context).push<MovimientoFormResult?>(
      MaterialPageRoute<MovimientoFormResult?>(
        builder: (_) => InventarioMovimientoFormScreen(
          almacenId: widget.almacenId,
          almacenName: _almacenTitle,
          mode: mode,
          existencias: items,
          user: widget.user,
          service: widget.service,
          onRefreshPermissions: widget.onRefreshPermissions,
          initialInsumoId: insumoId,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final mov = result.movimiento;
    final saldoText = mov.formattedSaldoPosterior != null
        ? ' Saldo actualizado: ${mov.formattedSaldoPosterior}.'
        : '';
    setState(() {
      _notice =
          '${mov.tipoNombre} registrado (${mov.formattedQuantity} de ${mov.insumoNombre}).$saldoText';
    });
    await _loadAll();
  }

  void _backToList() {
    final navigator = Navigator.of(context);
    final listRoute = AppModule.almacenes.route;
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
    if (!_loading && _loadErrorStatus == 403) {
      return ModuleAccessDenied(
        title: 'Existencias del almacén',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver a almacenes',
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Inventario del almacén'),
        actions: [
          IconButton(
            tooltip: 'Actualizar inventario',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando existencias...')
            : _loadErrorStatus == 404
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'El almacén no está disponible',
                message: 'Vuelve a la lista de almacenes para actualizar.',
              )
            : _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _loadAll)
            : _content(context),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a almacenes'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final look = AppModule.almacenes.look;
    final items = _existencias?.items ?? const [];
    final canIngreso =
        items.isNotEmpty &&
        InventarioPermissions.canRegisterIngreso(widget.user);
    final canSalida =
        items.isNotEmpty &&
        InventarioPermissions.canRegisterSalida(widget.user);
    final canAjuste =
        items.isNotEmpty &&
        InventarioPermissions.canRegisterAjuste(widget.user);

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
                        ModuleMark(AppModule.almacenes, size: 48, solid: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Almacén #${widget.almacenId}',
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
                    Text(
                      _almacenTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              if (_notice case final notice?) ...[
                const SizedBox(height: 18),
                AppNotice(tone: AppNoticeTone.success, message: notice),
              ],
              if (canIngreso || canSalida || canAjuste) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (canIngreso)
                      FilledButton.icon(
                        key: const ValueKey('almacen.registrar_entrada'),
                        onPressed: () =>
                            _openMovimientoForm(MovimientoFormMode.ingreso),
                        icon: const Icon(Icons.move_to_inbox_rounded),
                        label: const Text('Registrar entrada'),
                      ),
                    if (canSalida)
                      OutlinedButton.icon(
                        key: const ValueKey('almacen.registrar_salida'),
                        onPressed: () =>
                            _openMovimientoForm(MovimientoFormMode.salida),
                        icon: const Icon(Icons.outbox_rounded),
                        label: const Text('Registrar salida'),
                      ),
                    if (canAjuste)
                      OutlinedButton.icon(
                        key: const ValueKey('almacen.registrar_ajuste'),
                        onPressed: () =>
                            _openMovimientoForm(MovimientoFormMode.ajuste),
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Registrar ajuste'),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('almacen.ver_alertas'),
                      onPressed: () => Navigator.of(context).pushNamed(
                        '${AppModule.almacenes.route}/alertas',
                        arguments: widget.almacenId,
                      ),
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Ver alertas'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              SectionTitle('Existencias autorizadas', color: look.tone),
              const SizedBox(height: 14),
              if (items.isEmpty)
                const AppNotice(
                  tone: AppNoticeTone.info,
                  message:
                      'Este almacén todavía no tiene productos con existencias registradas.',
                )
              else
                for (final item in items) ...[
                  _existenciaCard(context, item),
                  const SizedBox(height: 12),
                ],
              if (InventarioPermissions.canViewMovimientos(widget.user)) ...[
                const SizedBox(height: 16),
                SectionTitle('Historial de movimientos', color: look.tone),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const <String?, String>{
                      null: 'Todos',
                      'ingreso': 'Ingresos',
                      'salida': 'Salidas',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _naturalezaFilter == entry.key,
                        selectedColor: AppTheme.maize,
                        backgroundColor: AppTheme.surface,
                        side: const BorderSide(color: AppTheme.ink, width: 1.5),
                        onSelected: (_) {
                          setState(() => _naturalezaFilter = entry.key);
                          unawaited(_loadMovimientos());
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _movimientosSection(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _existenciaCard(BuildContext context, AlmacenExistencia item) {
    final theme = Theme.of(context).textTheme;
    return Container(
      key: ValueKey('existencia.${item.insumoId}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: item.existenciasBajas ? AppTheme.clay : AppTheme.ink,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.nombre, style: theme.titleLarge)),
              if (item.existenciasBajas)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.claySoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.clay, width: 1.5),
                  ),
                  child: const Text(
                    'Stock bajo',
                    style: TextStyle(
                      color: AppTheme.clay,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DetailField(label: 'Disponible', value: item.formattedDisponible),
          const Divider(height: 1),
          DetailField(label: 'Saldo físico', value: item.formattedFisica),
          if (item.minimo != null) ...[
            const Divider(height: 1),
            DetailField(
              label: 'Mínimo configurado',
              value: '${formatInventarioDecimal(item.minimo!)} ${item.unidad}',
            ),
          ],
          if (item.partidasVencidas.isNotEmpty || item.vencidaValue > 0) ...[
            const Divider(height: 1),
            DetailField(
              label: 'Vencido',
              value: item.partidasVencidas.isNotEmpty
                  ? item.partidasVencidas
                        .map(
                          (p) =>
                              '${formatInventarioDecimal(p.cantidadFisica)} ${item.unidad} (venció ${p.fechaVencimiento ?? 'sin fecha'})',
                        )
                        .join(' · ')
                  : item.formattedVencida,
            ),
          ],
          if (item.partidasProximasAVencer.isNotEmpty) ...[
            const Divider(height: 1),
            DetailField(
              label: 'Próximo a vencer',
              value: item.partidasProximasAVencer
                  .map(
                    (p) =>
                        '${formatInventarioDecimal(p.cantidadFisica)} ${item.unidad} (vence ${p.fechaVencimiento ?? 'sin fecha'})',
                  )
                  .join(' · '),
            ),
          ],
        ],
      ),
    );
  }

  Widget _movimientosSection(BuildContext context) {
    if (_loadingMovimientos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Cargando movimientos del almacén...'),
          ],
        ),
      );
    }
    if (_movimientosError case final err?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppNotice(tone: AppNoticeTone.error, message: err),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loadMovimientos,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar movimientos'),
            ),
          ),
        ],
      );
    }
    final items = _movimientos?.items ?? const [];
    if (items.isEmpty) {
      return const AppNotice(
        tone: AppNoticeTone.info,
        message: 'No hay movimientos registrados para este almacén.',
      );
    }
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mov in items) ...[
          Container(
            key: ValueKey('movimiento.${mov.id}'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppTheme.ink, width: 1.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${mov.tipoNombre} · ${mov.insumoNombre}',
                        style: theme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      mov.formattedQuantity,
                      style: theme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: mov.isSalida ? AppTheme.clay : AppTheme.forest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Fecha: ${mov.fecha}', style: theme.bodyMedium),
                if (mov.saldoAnterior != null && mov.saldoPosterior != null)
                  Text(
                    'Saldo: ${formatInventarioDecimal(mov.saldoAnterior!)} → ${formatInventarioDecimal(mov.saldoPosterior!)}${mov.unidad != null ? ' ${mov.unidad}' : ''}',
                    style: theme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (mov.destinoMotivo != null)
                  Text('Motivo: ${mov.destinoMotivo}', style: theme.bodyMedium),
                if (mov.usuarioNombre != null)
                  Text(
                    'Responsable: ${mov.usuarioNombre}',
                    style: theme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
