import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/planta_models.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

class PlantaRecepcionesScreen extends StatefulWidget {
  const PlantaRecepcionesScreen({
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
  State<PlantaRecepcionesScreen> createState() =>
      _PlantaRecepcionesScreenState();
}

class _PlantaRecepcionesScreenState extends State<PlantaRecepcionesScreen> {
  RecepcionesPlantaPage? _page;
  int _currentPage = 1;
  bool _showReceived = false;
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(_onExternalUpdate);
    if (PlantaPermissions.canViewRecepciones(widget.user)) {
      unawaited(_load(1));
    } else {
      _loading = false;
      _errorStatus = 403;
    }
  }

  @override
  void didUpdateWidget(covariant PlantaRecepcionesScreen oldWidget) {
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
      final result = await widget.service.loadRecepcionesPlanta(
        widget.user,
        recibido: _showReceived,
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
        _error = 'No se pudieron consultar las recepciones de planta.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlantaPermissions.canViewRecepciones(widget.user) ||
        (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Recepciones en planta',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recepciones en planta'),
        actions: [
          IconButton(
            tooltip: 'Actualizar recepciones',
            onPressed: _loading ? null : () => _load(_currentPage),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando recepciones...')
            : _error != null
            ? AppErrorState(
                message: _error!,
                onRetry: () => _load(_currentPage),
              )
            : _content(context, _page!),
      ),
    );
  }

  Widget _content(BuildContext context, RecepcionesPlantaPage page) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Pendientes'),
                    selected: !_showReceived,
                    selectedColor: AppTheme.maize,
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.ink, width: 1.5),
                    onSelected: (_) {
                      setState(() => _showReceived = false);
                      unawaited(_load(1));
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Recibidas'),
                    selected: _showReceived,
                    selectedColor: AppTheme.maize,
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.ink, width: 1.5),
                    onSelected: (_) {
                      setState(() => _showReceived = true);
                      unawaited(_load(1));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: page.items.isEmpty
              ? AppEmptyState(
                  icon: Icons.move_to_inbox_outlined,
                  tone: AppTheme.sprout,
                  ink: AppTheme.forest,
                  title: _showReceived
                      ? 'Sin recepciones registradas'
                      : 'Sin envíos pendientes de recepción',
                  message:
                      'Cuando existan envíos agrícolas hacia tu planta aparecerán aquí.',
                  action: OutlinedButton.icon(
                    onPressed: () => _load(1),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualizar'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: page.items.length,
                  itemBuilder: (context, index) =>
                      _card(context, page.items[index]),
                ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, RecepcionPlantaRecord record) {
    final theme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PressableCard(
            key: ValueKey('planta.recepcion.${record.pedidoId}'),
            onTap: () => Navigator.of(context).pushNamed(
              '${AppModule.recepcionesPlanta.route}/${record.pedidoId}',
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
                Text(
                  '${record.lineas.length} ${record.lineas.length == 1 ? 'línea' : 'líneas'} de materia prima',
                  style: theme.bodyMedium,
                ),
                if (record.lineas.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Origen: ${record.lineas.map((l) => l.origenLoteLabel).toSet().join(', ')}',
                    style: theme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (record.isReceived) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Recibido: ${record.lineas.map((l) => l.formattedRecibida ?? l.formattedEnviada).join(' · ')}',
                      style: theme.bodyMedium,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
