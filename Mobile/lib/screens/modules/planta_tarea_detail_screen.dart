import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/planta_models.dart';
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

class PlantaTareaDetailScreen extends StatefulWidget {
  const PlantaTareaDetailScreen({
    super.key,
    required this.asignacionId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.onTareaUpdated,
  });

  final int asignacionId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final VoidCallback? onTareaUpdated;

  @override
  State<PlantaTareaDetailScreen> createState() =>
      _PlantaTareaDetailScreenState();
}

class _PlantaTareaDetailScreenState extends State<PlantaTareaDetailScreen> {
  TareaPlantaDetail? _detail;
  bool _loading = true;
  String? _loadError;
  int? _loadErrorStatus;

  @override
  void initState() {
    super.initState();
    if (PlantaPermissions.canViewTareas(widget.user)) {
      unawaited(_load());
    } else {
      _loading = false;
      _loadErrorStatus = 403;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _loadErrorStatus = null;
    });
    try {
      final detail = await widget.service.loadTareaPlantaDetail(
        widget.user,
        widget.asignacionId,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
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
        _loadError = 'No se pudo consultar el detalle de la tarea de planta.';
      });
    }
  }

  void _backToList() {
    final navigator = Navigator.of(context);
    final listRoute = AppModule.tareasPlanta.route;
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
    if (!PlantaPermissions.canViewTareas(widget.user) ||
        (!_loading && _loadErrorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Detalle de tarea de planta',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver a tareas de planta',
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Detalle de tarea'),
        actions: [
          IconButton(
            tooltip: 'Actualizar tarea',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando detalle de la etapa...')
            : _loadErrorStatus == 404
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'La tarea ya no está disponible',
                message:
                    'Vuelve a la lista de tareas de planta para actualizar.',
              )
            : _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _load)
            : _content(context, _detail!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a tareas de planta'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, TareaPlantaDetail detail) {
    final look = AppModule.tareasPlanta.look;
    final tarea = detail.tarea;
    final machineStatus = tarea.maquinaActiva
        ? 'Disponible'
        : 'En mantenimiento';

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
                        ModuleMark(
                          AppModule.tareasPlanta,
                          size: 48,
                          solid: true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Etapa ${tarea.orden} · Tarea #${tarea.id}',
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
                    Semantics(
                      header: true,
                      child: Text(
                        tarea.procesoNombre,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RecordStatusBadge(status: tarea.estadoLabel),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle('Proceso y etapa', color: look.tone),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: AppTheme.ink, width: 2),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DetailField(label: 'Proceso', value: tarea.procesoNombre),
                    const Divider(height: 1),
                    DetailField(
                      label: 'Etapa del proceso',
                      value: 'Etapa ${tarea.orden}',
                    ),
                    const Divider(height: 1),
                    DetailField(
                      label: 'Lote de producción',
                      value: tarea.loteLabel,
                    ),
                    if (tarea.loteProducto != null) ...[
                      const Divider(height: 1),
                      DetailField(
                        label: 'Producto',
                        value: tarea.loteProducto!,
                      ),
                    ],
                    if (tarea.observaciones != null) ...[
                      const Divider(height: 1),
                      DetailField(
                        label: 'Observaciones',
                        value: tarea.observaciones!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle('Máquina asignada', color: look.tone),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: AppTheme.ink, width: 2),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DetailField(label: 'Máquina', value: tarea.maquinaNombre),
                    if (tarea.maquinaCodigo != null) ...[
                      const Divider(height: 1),
                      DetailField(
                        label: 'Código de máquina',
                        value: tarea.maquinaCodigo!,
                      ),
                    ],
                    const Divider(height: 1),
                    DetailField(
                      label: 'Estado de máquina',
                      value: machineStatus,
                    ),
                  ],
                ),
              ),
              if (detail.resultadoParametros.isNotEmpty) ...[
                const SizedBox(height: 24),
                SectionTitle('Resultados registrados', color: look.tone),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.ink, width: 2),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var i = 0;
                        i < detail.resultadoParametros.length;
                        i++
                      ) ...[
                        if (i > 0) const Divider(height: 1),
                        DetailField(
                          label: detail.resultadoParametros[i].nombre,
                          value: detail.resultadoParametros[i].formattedValue,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
