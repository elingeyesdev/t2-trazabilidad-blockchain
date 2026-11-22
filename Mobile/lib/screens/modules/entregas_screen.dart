import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/entrega_models.dart';
import '../../models/qr_envio_models.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

enum _EntregasTab { rutas, agricola, distribucion }

class EntregasScreen extends StatefulWidget {
  const EntregasScreen({
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
  State<EntregasScreen> createState() => _EntregasScreenState();
}

class _EntregasScreenState extends State<EntregasScreen> {
  late _EntregasTab _tab;
  RutasEntregaPage? _rutasPage;
  List<EnvioResumen> _envios = const [];
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  List<_EntregasTab> get _allowedTabs => [
    if (EntregaPermissions.canViewRutas(widget.user)) _EntregasTab.rutas,
    if (EntregaPermissions.canViewEnviosAgricolas(widget.user))
      _EntregasTab.agricola,
    if (EntregaPermissions.canViewEnviosDistribucion(widget.user))
      _EntregasTab.distribucion,
  ];

  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(_onExternalUpdate);
    final allowed = _allowedTabs;
    if (allowed.isNotEmpty) {
      _tab = allowed.first;
      unawaited(_load());
    } else {
      _tab = _EntregasTab.rutas;
      _loading = false;
      _errorStatus = 403;
    }
  }

  @override
  void didUpdateWidget(covariant EntregasScreen oldWidget) {
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
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = null;
    });
    try {
      if (_tab == _EntregasTab.rutas) {
        final page = await widget.service.loadRutasEntrega(widget.user);
        if (!mounted) return;
        setState(() {
          _rutasPage = page;
          _loading = false;
        });
      } else {
        final tipo = _tab == _EntregasTab.agricola
            ? EnvioTipo.agricola
            : EnvioTipo.distribucion;
        final items = await widget.service.loadEnviosMovilList(
          widget.user,
          tipo: tipo,
        );
        if (!mounted) return;
        setState(() {
          _envios = items;
          _loading = false;
        });
      }
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
        _error = 'No se pudieron consultar tus envíos asignados.';
      });
    }
  }

  String _tabLabel(_EntregasTab tab) => switch (tab) {
    _EntregasTab.rutas => 'Rutas de entrega',
    _EntregasTab.agricola => 'Envíos agrícolas',
    _EntregasTab.distribucion => 'Distribución',
  };

  @override
  Widget build(BuildContext context) {
    if (!EntregaPermissions.canViewAny(widget.user) ||
        (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Envíos y entregas',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    final allowed = _allowedTabs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Envíos y entregas'),
        actions: [
          if (QrPermissions.canUseQr(widget.user))
            IconButton(
              key: const ValueKey('entregas.qr_btn'),
              tooltip: 'Leer código QR',
              onPressed: () => Navigator.of(context).pushNamed('/modules/qr'),
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          IconButton(
            key: const ValueKey('entregas.actualizar'),
            tooltip: 'Actualizar envíos',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (allowed.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final tab in allowed) ...[
                            ChoiceChip(
                              key: ValueKey('entregas.tab.${tab.name}'),
                              label: Text(_tabLabel(tab)),
                              selected: _tab == tab,
                              selectedColor: AppTheme.maize,
                              backgroundColor: AppTheme.surface,
                              side: const BorderSide(
                                color: AppTheme.ink,
                                width: 1.5,
                              ),
                              onSelected: (_) {
                                if (_tab == tab) return;
                                setState(() => _tab = tab);
                                unawaited(_load());
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const AppLoading(message: 'Cargando envíos...')
                  : _error != null
                  ? AppErrorState(message: _error!, onRetry: _load)
                  : _tab == _EntregasTab.rutas
                  ? _rutasList(context, _rutasPage!)
                  : _enviosList(context, _envios),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rutasList(BuildContext context, RutasEntregaPage page) {
    if (page.items.isEmpty) {
      return AppEmptyState(
        icon: Icons.route_outlined,
        tone: AppTheme.sprout,
        ink: AppTheme.forest,
        title: 'Sin rutas asignadas',
        message: 'Cuando tengas rutas de entrega asignadas aparecerán aquí.',
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Actualizar'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: page.items.length,
        itemBuilder: (context, index) => _rutaCard(context, page.items[index]),
      ),
    );
  }

  Widget _rutaCard(BuildContext context, RutaEntregaRecord ruta) {
    final theme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PressableCard(
            key: ValueKey('entregas.ruta.${ruta.id}'),
            onTap: () => Navigator.of(
              context,
            ).pushNamed('/modules/entregas/ruta/${ruta.id}'),
            color: AppTheme.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: RecordStatusBadge(status: ruta.estadoLabel),
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
                Text(ruta.nombre, style: theme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  '${ruta.paradasCount} ${ruta.paradasCount == 1 ? 'parada' : 'paradas'}',
                  style: theme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (ruta.fechaSalida != null) ...[
                  const SizedBox(height: 4),
                  Text('Salida: ${ruta.fechaSalida}', style: theme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _enviosList(BuildContext context, List<EnvioResumen> items) {
    if (items.isEmpty) {
      return AppEmptyState(
        icon: Icons.local_shipping_outlined,
        tone: AppTheme.sprout,
        ink: AppTheme.forest,
        title: 'Sin envíos asignados',
        message: 'No tienes envíos activos en este trayecto.',
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Actualizar'),
        ),
      );
    }

    final theme = Theme.of(context).textTheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final envio = items[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: PressableCard(
                key: ValueKey('entregas.envio.${envio.tipo.value}.${envio.id}'),
                onTap: () => Navigator.of(
                  context,
                ).pushNamed('/modules/envios/${envio.tipo.value}/${envio.id}'),
                color: AppTheme.surface,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: RecordStatusBadge(status: envio.estadoLabel),
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
                    Text(envio.referencia, style: theme.titleLarge),
                    if (envio.destinos.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Destino: ${envio.destinos.map((d) => d.label).join(', ')}',
                        style: theme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
