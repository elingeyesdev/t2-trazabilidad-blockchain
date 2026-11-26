import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/planta_models.dart';
import '../../navigation/app_module.dart';
import '../../navigation/app_routes.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/record_card.dart';
import 'module_access_denied.dart';

class PlantaTareasScreen extends StatefulWidget {
  const PlantaTareasScreen({
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
  State<PlantaTareasScreen> createState() => _PlantaTareasScreenState();
}

class _PlantaTareasScreenState extends State<PlantaTareasScreen> {
  TareasPlantaPage? _page;
  int _currentPage = 1;
  String? _estadoFilter;
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(_onExternalUpdate);
    if (PlantaPermissions.canViewTareas(widget.user)) {
      unawaited(_load(1));
    } else {
      _loading = false;
      _errorStatus = 403;
    }
  }

  @override
  void didUpdateWidget(covariant PlantaTareasScreen oldWidget) {
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
      final result = await widget.service.loadTareasPlanta(
        widget.user,
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
        _error = 'No se pudieron consultar tus tareas de planta.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlantaPermissions.canViewTareas(widget.user) ||
        (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Tareas de planta',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tareas de planta'),
        actions: [
          IconButton(
            tooltip: 'Actualizar tareas',
            onPressed: _loading ? null : () => _load(_currentPage),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(
                message: 'Cargando tareas asignadas...',
                shape: LoadingShape.list,
              )
            : _error != null
            ? AppErrorState(
                message: _error!,
                onRetry: () => _load(_currentPage),
              )
            : _content(context, _page!),
      ),
    );
  }

  Widget _content(BuildContext context, TareasPlantaPage page) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in const <String?, String>{
                      null: 'Todas',
                      'pendiente': 'Pendientes',
                      'programada': 'Programadas',
                      'completada': 'Completadas',
                    }.entries) ...[
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _estadoFilter == entry.key,
                        selectedColor: AppTheme.maize,
                        backgroundColor: AppTheme.surface,
                        side: const BorderSide(color: AppTheme.ink, width: 1.5),
                        onSelected: (_) {
                          setState(() => _estadoFilter = entry.key);
                          unawaited(_load(1));
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
          child: page.items.isEmpty
              ? AppEmptyState(
                  icon: Icons.precision_manufacturing_outlined,
                  tone: AppTheme.sprout,
                  ink: AppTheme.forest,
                  title: 'No hay tareas de planta para mostrar',
                  message:
                      'Cuando tengas etapas asignadas en planta aparecerán aquí en el orden del proceso.',
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
                      _taskCard(context, page.items[index]),
                ),
        ),
        if (page.lastPage > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: page.currentPage > 1
                      ? () => _load(page.currentPage - 1)
                      : null,
                  child: const Text('Anterior'),
                ),
                const SizedBox(width: 12),
                Text('Página ${page.currentPage} de ${page.lastPage}'),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: page.currentPage < page.lastPage
                      ? () => _load(page.currentPage + 1)
                      : null,
                  child: const Text('Siguiente'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _taskCard(BuildContext context, TareaPlantaSummary tarea) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: RecordCard(
            key: ValueKey('planta.tarea.${tarea.id}'),
            module: AppModule.tareasPlanta,
            eyebrow: 'Etapa ${tarea.orden}',
            title: tarea.procesoNombre,
            status: tarea.estadoLabel,
            facts: [('', tarea.loteLabel), ('Máquina', tarea.maquinaLabel)],
            onTap: () => Navigator.of(
              context,
            ).pushNamed(AppRoutes.detalle(AppModule.tareasPlanta, tarea.id)),
          ),
        ),
      ),
    );
  }
}
