import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/inventario_models.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import 'module_access_denied.dart';

class InventarioAlertasScreen extends StatefulWidget {
  const InventarioAlertasScreen({
    super.key,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.initialAlmacenId,
  });

  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final int? initialAlmacenId;

  @override
  State<InventarioAlertasScreen> createState() =>
      _InventarioAlertasScreenState();
}

class _InventarioAlertasScreenState extends State<InventarioAlertasScreen> {
  List<AlmacenFiltroOption> _almacenes = const [];
  List<InventarioAlertItem> _alerts = const [];
  int? _selectedAlmacenId;
  InventarioAlertKind? _kindFilter;
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  @override
  void initState() {
    super.initState();
    _selectedAlmacenId = widget.initialAlmacenId;
    if (InventarioPermissions.canViewExistencias(widget.user)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = null;
    });
    try {
      final almacenes = await widget.service.loadAuthorizedAlmacenes(
        widget.user,
      );
      if (!mounted) return;
      final validSelected =
          _selectedAlmacenId != null &&
              almacenes.any((a) => a.id == _selectedAlmacenId)
          ? _selectedAlmacenId
          : null;
      final targets = validSelected == null
          ? almacenes
          : almacenes.where((a) => a.id == validSelected).toList();
      final collected = <InventarioAlertItem>[];
      for (final almacen in targets) {
        final page = await widget.service.loadAlmacenExistencias(
          widget.user,
          almacen.id,
        );
        collected.addAll(
          buildAlertsFromExistencias(
            almacenId: almacen.id,
            almacenNombre: almacen.name,
            items: page.items,
          ),
        );
      }
      collected.sort((a, b) {
        final kindCmp = a.kind.index.compareTo(b.kind.index);
        if (kindCmp != 0) return kindCmp;
        final dateA = a.fechaVencimiento ?? '9999-99-99';
        final dateB = b.fechaVencimiento ?? '9999-99-99';
        final dateCmp = dateA.compareTo(dateB);
        if (dateCmp != 0) return dateCmp;
        return a.productoNombre.compareTo(b.productoNombre);
      });
      if (!mounted) return;
      setState(() {
        _almacenes = almacenes;
        _selectedAlmacenId = validSelected;
        _alerts = collected;
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
        _error =
            'No se pudieron consultar las alertas de inventario. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!InventarioPermissions.canViewExistencias(widget.user) ||
        (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Alertas de inventario',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas de inventario'),
        actions: [
          IconButton(
            tooltip: 'Actualizar alertas',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Consultando alertas de inventario...')
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final vencidosCount = _alerts
        .where((a) => a.kind == InventarioAlertKind.vencido)
        .length;
    final proximosCount = _alerts
        .where((a) => a.kind == InventarioAlertKind.proximoAVencer)
        .length;
    final bajosCount = _alerts
        .where((a) => a.kind == InventarioAlertKind.stockBajo)
        .length;

    final filtered = _kindFilter == null
        ? _alerts
        : _alerts.where((a) => a.kind == _kindFilter).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int?>(
                key: const ValueKey('alertas.almacen_filter'),
                initialValue: _selectedAlmacenId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por almacén autorizado',
                  prefixIcon: Icon(Icons.warehouse_outlined),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todos los almacenes autorizados'),
                  ),
                  for (final almacen in _almacenes)
                    DropdownMenuItem<int?>(
                      value: almacen.id,
                      child: Text(
                        almacen.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _selectedAlmacenId = value);
                  unawaited(_load());
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Todas (${_alerts.length})'),
                    selected: _kindFilter == null,
                    selectedColor: AppTheme.maize,
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.ink, width: 1.5),
                    onSelected: (_) => setState(() => _kindFilter = null),
                  ),
                  ChoiceChip(
                    label: Text('Vencidos ($vencidosCount)'),
                    selected: _kindFilter == InventarioAlertKind.vencido,
                    selectedColor: AppTheme.claySoft,
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.ink, width: 1.5),
                    onSelected: (_) => setState(
                      () => _kindFilter = InventarioAlertKind.vencido,
                    ),
                  ),
                  ChoiceChip(
                    label: Text('Próximos a vencer ($proximosCount)'),
                    selected: _kindFilter == InventarioAlertKind.proximoAVencer,
                    selectedColor: AppTheme.maizeSoft,
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.ink, width: 1.5),
                    onSelected: (_) => setState(
                      () => _kindFilter = InventarioAlertKind.proximoAVencer,
                    ),
                  ),
                  ChoiceChip(
                    label: Text('Existencias bajas ($bajosCount)'),
                    selected: _kindFilter == InventarioAlertKind.stockBajo,
                    selectedColor: AppTheme.maize,
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.ink, width: 1.5),
                    onSelected: (_) => setState(
                      () => _kindFilter = InventarioAlertKind.stockBajo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (filtered.isEmpty)
                AppEmptyState(
                  icon: Icons.verified_outlined,
                  tone: AppTheme.sprout,
                  ink: AppTheme.forest,
                  title: 'Sin alertas en esta vista',
                  message:
                      'No hay productos vencidos, próximos a vencer ni con existencias por debajo del mínimo para el filtro seleccionado.',
                  action: OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualizar'),
                  ),
                )
              else
                for (final alert in filtered) ...[
                  _alertCard(context, alert),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertCard(BuildContext context, InventarioAlertItem alert) {
    final theme = Theme.of(context).textTheme;
    final (
      IconData icon,
      Color bg,
      Color fg,
      Color border,
    ) = switch (alert.kind) {
      InventarioAlertKind.vencido => (
        Icons.error_outline_rounded,
        AppTheme.claySoft,
        AppTheme.clay,
        AppTheme.clay,
      ),
      InventarioAlertKind.proximoAVencer => (
        Icons.schedule_rounded,
        AppTheme.maizeSoft,
        const Color(0xFF5F4100),
        const Color(0xFF8A5E00),
      ),
      InventarioAlertKind.stockBajo => (
        Icons.inventory_2_outlined,
        AppTheme.maizeSoft,
        AppTheme.ink,
        AppTheme.ink,
      ),
    };

    return PressableCard(
      onTap: () => Navigator.of(context).pushNamed(
        '${AppModule.almacenes.route}/${alert.almacenId}',
        arguments: alert.almacenNombre,
      ),
      color: AppTheme.surface,
      borderColor: border,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: border, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      alert.statusLabel,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: AppTheme.inkSoft,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(alert.productoNombre, style: theme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Almacén: ${alert.almacenNombre}',
            style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(alert.detailSummary, style: theme.bodyMedium),
          if (alert.referenciaPartida != null) ...[
            const SizedBox(height: 4),
            Text('Partida: ${alert.referenciaPartida}', style: theme.bodySmall),
          ],
        ],
      ),
    );
  }
}
