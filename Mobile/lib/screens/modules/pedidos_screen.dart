import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/pedido_models.dart';
import '../../models/qr_envio_models.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({
    super.key,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.updates,
  });

  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final ValueListenable<int>? updates;

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  List<(String?, String)> get _estadoFilters => [
    (null, 'Todos'),
    ('pendiente', 'Pendiente'),
    ('confirmado', 'Confirmado'),
    ('rechazado', 'Rechazado'),
    if (_tipo == PedidoTipo.agricola) ('sin asignacion', 'Pendiente agrícola'),
  ];

  late PedidoTipo _tipo;
  String? _estadoFilter;
  PedidosPage? _page;
  int _currentPage = 1;
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  List<PedidoTipo> get _allowedTipos => [
    if (PedidoPermissions.canViewDistribucion(widget.user))
      PedidoTipo.distribucion,
    if (PedidoPermissions.canViewAgricola(widget.user)) PedidoTipo.agricola,
  ];

  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(_onExternalUpdate);
    final allowed = _allowedTipos;
    if (allowed.isNotEmpty) {
      _tipo = allowed.first;
      unawaited(_load(1));
    } else {
      _tipo = PedidoTipo.distribucion;
      _loading = false;
      _errorStatus = 403;
    }
  }

  @override
  void didUpdateWidget(covariant PedidosScreen oldWidget) {
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
    if (!mounted) return;
    unawaited(_load(_currentPage));
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = null;
      _currentPage = page;
    });
    try {
      final result = await widget.service.loadPedidosMovil(
        widget.user,
        tipo: _tipo,
        estado: _estadoFilter,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _page = result;
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
        _error = 'No se pudieron consultar los pedidos.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PedidoPermissions.canViewAny(widget.user) ||
        (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: AppModule.pedidos.label,
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    final allowed = _allowedTipos;
    final canCreate = PedidoPermissions.canCreateAny(widget.user);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        actions: [
          if (QrPermissions.canUseQr(widget.user))
            IconButton(
              key: const ValueKey('pedidos.escanear_qr'),
              tooltip: 'Leer código QR',
              onPressed: () => Navigator.of(context).pushNamed('/modules/qr'),
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          if (canCreate)
            IconButton(
              key: const ValueKey('pedidos.nuevo'),
              tooltip: 'Nuevo pedido',
              onPressed: () => Navigator.of(
                context,
              ).pushNamed('${AppModule.pedidos.route}/nuevo'),
              icon: const Icon(Icons.add_rounded),
            ),
          IconButton(
            tooltip: 'Actualizar pedidos',
            onPressed: _loading ? null : () => _load(_currentPage),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (allowed.length > 1 || canCreate) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (allowed.length > 1)
                              for (final tipo in allowed)
                                ChoiceChip(
                                  key: ValueKey('pedidos.tipo.${tipo.value}'),
                                  label: Text(tipo.label),
                                  selected: _tipo == tipo,
                                  selectedColor: AppTheme.maize,
                                  backgroundColor: AppTheme.surface,
                                  side: const BorderSide(
                                    color: AppTheme.ink,
                                    width: 1.5,
                                  ),
                                  onSelected: (_) {
                                    if (_tipo == tipo) return;
                                    setState(() {
                                      _tipo = tipo;
                                      _estadoFilter = null;
                                    });
                                    unawaited(_load(1));
                                  },
                                ),
                            if (canCreate)
                              FilledButton.icon(
                                key: const ValueKey('pedidos.crear_btn'),
                                onPressed: () => Navigator.of(
                                  context,
                                ).pushNamed('${AppModule.pedidos.route}/nuevo'),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text(
                                  _tipo == PedidoTipo.agricola
                                      ? 'Nuevo envío'
                                      : 'Nuevo pedido',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final (value, label) in _estadoFilters) ...[
                              ChoiceChip(
                                key: ValueKey(
                                  'pedidos.estado.${value ?? 'todos'}',
                                ),
                                label: Text(label),
                                selected: _estadoFilter == value,
                                selectedColor: AppTheme.sprout,
                                backgroundColor: AppTheme.surface,
                                side: const BorderSide(
                                  color: AppTheme.ink,
                                  width: 1.2,
                                ),
                                onSelected: (_) {
                                  if (_estadoFilter == value) return;
                                  setState(() => _estadoFilter = value);
                                  unawaited(_load(1));
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const AppLoading(message: 'Cargando pedidos...')
                  : _error != null
                  ? AppErrorState(
                      message: _error!,
                      onRetry: () => _load(_currentPage),
                    )
                  : _list(context, _page!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, PedidosPage page) {
    if (page.items.isEmpty) {
      return AppEmptyState(
        icon: Icons.receipt_long_outlined,
        tone: AppTheme.sprout,
        ink: AppTheme.forest,
        title: 'Sin pedidos de ${_tipo.label.toLowerCase()}',
        message: 'Cuando existan solicitudes autorizadas aparecerán aquí.',
        action: OutlinedButton.icon(
          onPressed: () => _load(1),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Actualizar'),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: page.items.length + (page.lastPage > 1 ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == page.items.length) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      onPressed: page.currentPage > 1
                          ? () => _load(page.currentPage - 1)
                          : null,
                      child: const Text('Anterior'),
                    ),
                    Text('Página ${page.currentPage} de ${page.lastPage}'),
                    OutlinedButton(
                      onPressed: page.currentPage < page.lastPage
                          ? () => _load(page.currentPage + 1)
                          : null,
                      child: const Text('Siguiente'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return _card(context, page.items[index]);
      },
    );
  }

  Widget _card(BuildContext context, PedidoRecord record) {
    final theme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PressableCard(
            key: ValueKey('pedidos.item.${record.tipo.value}.${record.id}'),
            onTap: () => Navigator.of(context).pushNamed(
              '${AppModule.pedidos.route}/${record.tipo.value}/${record.id}',
            ),
            color: AppTheme.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: RecordStatusBadge(status: record.estadoLabel),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 26,
                      color: AppTheme.ink,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(record.numeroSolicitud, style: theme.titleLarge),
                const SizedBox(height: 6),
                if (record.origen?.direccion != null) ...[
                  Text(
                    'Origen: ${record.origen!.direccion}',
                    style: theme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  'Destino: ${record.destino.label}',
                  style: theme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.detalles.length} ${record.detalles.length == 1 ? 'producto' : 'productos'}',
                  style: theme.bodyMedium,
                ),
                if (record.envio?.transportistaNombre != null ||
                    record.envio?.vehiculoPlaca != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (record.envio?.transportistaNombre != null)
                        'Chofer: ${record.envio!.transportistaNombre}',
                      if (record.envio?.vehiculoPlaca != null)
                        'Vehículo: ${record.envio!.vehiculoPlaca}',
                      if (record.envio?.costoBs != null)
                        'Bs ${record.envio!.costoBs!.toStringAsFixed(0)}',
                    ].join(' · '),
                    style: theme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
