import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/actividad_models.dart';
import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/cosecha_models.dart';
import '../../models/inventario_models.dart';
import '../../models/lote_models.dart';
import '../../models/module_page.dart';
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
import 'actividad_form_screen.dart';
import 'cosecha_form_screen.dart';
import 'lote_form_screen.dart';
import 'module_access_denied.dart';

class ModuleScreen extends StatefulWidget {
  const ModuleScreen({
    super.key,
    required this.module,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.loteUpdates,
    this.actividadUpdates,
    this.cosechaUpdates,
  });

  final AppModule module;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final ValueListenable<int>? loteUpdates;
  final ValueListenable<int>? actividadUpdates;
  final ValueListenable<int>? cosechaUpdates;

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

enum _ActivityFilter { all, pending, completed }

class _ModuleScreenState extends State<ModuleScreen> {
  late Future<ModulePage> _request = widget.service.load(
    widget.module,
    widget.user,
  );
  int _page = 1;
  final _searchController = TextEditingController();
  bool _searching = false;
  _ActivityFilter _activityFilter = _ActivityFilter.all;

  bool get _supportsSearch =>
      widget.module == AppModule.lotes ||
      widget.module == AppModule.actividades ||
      widget.module == AppModule.producciones ||
      widget.module == AppModule.almacenes;

  bool get _canCreateLote =>
      widget.module == AppModule.lotes &&
      LotePermissions.canCreate(widget.user);

  bool get _canAssignActividad =>
      widget.module == AppModule.actividades &&
      ActividadPermissions.canAssign(widget.user);

  bool get _canCreateCosecha =>
      widget.module == AppModule.producciones &&
      CosechaPermissions.canCreate(widget.user);

  bool get _canViewInventarioAlertas =>
      widget.module == AppModule.almacenes &&
      InventarioPermissions.canViewExistencias(widget.user);

  bool get _canOpenPedidosGestion =>
      widget.module == AppModule.pedidos &&
      PedidoPermissions.canViewAny(widget.user);

  @override
  void initState() {
    super.initState();
    widget.loteUpdates?.addListener(_onLoteUpdated);
    widget.actividadUpdates?.addListener(_onActividadUpdated);
    widget.cosechaUpdates?.addListener(_onCosechaUpdated);
  }

  @override
  void didUpdateWidget(covariant ModuleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loteUpdates != widget.loteUpdates) {
      oldWidget.loteUpdates?.removeListener(_onLoteUpdated);
      widget.loteUpdates?.addListener(_onLoteUpdated);
    }
    if (oldWidget.actividadUpdates != widget.actividadUpdates) {
      oldWidget.actividadUpdates?.removeListener(_onActividadUpdated);
      widget.actividadUpdates?.addListener(_onActividadUpdated);
    }
    if (oldWidget.cosechaUpdates != widget.cosechaUpdates) {
      oldWidget.cosechaUpdates?.removeListener(_onCosechaUpdated);
      widget.cosechaUpdates?.addListener(_onCosechaUpdated);
    }
  }

  @override
  void dispose() {
    widget.loteUpdates?.removeListener(_onLoteUpdated);
    widget.actividadUpdates?.removeListener(_onActividadUpdated);
    widget.cosechaUpdates?.removeListener(_onCosechaUpdated);
    _searchController.dispose();
    super.dispose();
  }

  void _onLoteUpdated() {
    if (!mounted || widget.module != AppModule.lotes) return;
    _load(_page);
  }

  void _onActividadUpdated() {
    if (!mounted || widget.module != AppModule.actividades) return;
    _load(_page);
  }

  void _onCosechaUpdated() {
    if (!mounted || widget.module != AppModule.producciones) return;
    _load(_page);
  }

  Future<void> _createLote() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(
      context,
    ).pushNamed('${AppModule.lotes.route}/nuevo');
    if (!mounted) return;
    if (result is LoteFormResult) {
      _load(1);
      await Navigator.of(context).pushNamed(
        '${AppModule.lotes.route}/${result.record.id}',
        arguments:
            'El lote "${result.record.title}" se registró correctamente.',
      );
    }
  }

  Future<void> _assignActividad() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(
      context,
    ).pushNamed('${AppModule.actividades.route}/nueva');
    if (!mounted) return;
    if (result is ActividadFormResult) {
      _load(1);
      await Navigator.of(context).pushNamed(
        '${AppModule.actividades.route}/${result.record.id}',
        arguments:
            'La actividad "${result.record.title}" fue asignada correctamente.',
      );
    }
  }

  Future<void> _createCosecha() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(
      context,
    ).pushNamed('${AppModule.producciones.route}/nueva');
    if (!mounted) return;
    if (result is CosechaFormResult) {
      _load(1);
      await Navigator.of(context).pushNamed(
        '${AppModule.producciones.route}/${result.record.id}',
        arguments: 'La cosecha #${result.record.id} se registró correctamente.',
      );
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
    });
  }

  void _closeSearch() {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = false;
      _searchController.clear();
    });
  }

  void _openRecord(ModuleRecord record) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pushNamed(
      '${widget.module.route}/${record.id}',
      arguments: widget.module == AppModule.almacenes ? record.title : null,
    );
  }

  String _normalize(String value) {
    var result = value.trim().toLowerCase();
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
    };
    for (final entry in accents.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  void _load(int page) {
    FocusScope.of(context).unfocus();
    setState(() {
      _page = page;
      _request = widget.service.load(widget.module, widget.user, page: page);
      // FutureBuilder se suscribe en el siguiente cuadro.
      _request.ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ModulePage>(
      future: _request,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        if (!loading &&
            snapshot.error is ApiException &&
            (snapshot.error! as ApiException).statusCode == 403) {
          return ModuleAccessDenied(
            title: widget.module.label,
            onRefreshPermissions: widget.onRefreshPermissions,
          );
        }
        return PopScope(
          canPop: !_searching,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _searching) _closeSearch();
          },
          child: Scaffold(
            appBar: AppBar(
              leading: _searching
                  ? IconButton(
                      tooltip: 'Cerrar búsqueda',
                      onPressed: _closeSearch,
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  : null,
              title: _searching
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      decoration: InputDecoration(
                        hintText:
                            snapshot.data != null && snapshot.data!.lastPage > 1
                            ? 'Buscar en esta página'
                            : 'Buscar ${widget.module.label.toLowerCase()}',
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    )
                  : Text(widget.module.label),
              actions: [
                if (_supportsSearch && !_searching)
                  IconButton(
                    tooltip: 'Buscar ${widget.module.label.toLowerCase()}',
                    onPressed: loading || snapshot.hasError || !snapshot.hasData
                        ? null
                        : () => setState(() => _searching = true),
                    icon: const Icon(Icons.search_rounded),
                  ),
                if (_searching)
                  IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: _searchController.text.isEmpty
                        ? null
                        : _clearSearch,
                    icon: const Icon(Icons.close_rounded),
                  ),
                IconButton(
                  onPressed: loading ? null : () => _load(1),
                  tooltip: 'Actualizar lista',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            floatingActionButton:
                (_canCreateLote ||
                        _canAssignActividad ||
                        _canCreateCosecha ||
                        _canViewInventarioAlertas ||
                        _canOpenPedidosGestion) &&
                    !loading &&
                    !snapshot.hasError
                ? FloatingActionButton.extended(
                    heroTag: null,
                    backgroundColor: AppTheme.maize,
                    foregroundColor: AppTheme.ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: AppTheme.border, width: 1),
                    ),
                    onPressed: _canCreateLote
                        ? _createLote
                        : (_canAssignActividad
                              ? _assignActividad
                              : (_canCreateCosecha
                                    ? _createCosecha
                                    : (_canViewInventarioAlertas
                                          ? () => Navigator.of(context).pushNamed(
                                              '${AppModule.almacenes.route}/alertas',
                                            )
                                          : () => Navigator.of(context).pushNamed(
                                              '${AppModule.pedidos.route}/gestion',
                                            )))),
                    icon: Icon(
                      _canCreateLote
                          ? Icons.add_rounded
                          : (_canAssignActividad
                                ? Icons.assignment_add
                                : (_canCreateCosecha
                                      ? Icons.grass_rounded
                                      : (_canViewInventarioAlertas
                                            ? Icons
                                                  .notifications_active_outlined
                                            : Icons.receipt_long_rounded))),
                    ),
                    label: Text(
                      _canCreateLote
                          ? 'Nuevo lote'
                          : (_canAssignActividad
                                ? 'Asignar actividad'
                                : (_canCreateCosecha
                                      ? 'Registrar cosecha'
                                      : (_canViewInventarioAlertas
                                            ? 'Ver alertas'
                                            : 'Solicitudes y pedidos'))),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  )
                : null,
            body: SafeArea(child: _content(snapshot)),
          ),
        );
      },
    );
  }

  Widget _content(AsyncSnapshot<ModulePage> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return AppLoading(
        message: 'Cargando ${widget.module.label.toLowerCase()}...',
      );
    }
    if (snapshot.hasError) {
      final error = snapshot.error;
      return AppErrorState(
        message: error is ApiException
            ? error.message
            : 'No se pudieron consultar los registros.',
        onRetry: () => _load(_page),
      );
    }
    return _records(snapshot.requireData);
  }

  Widget _records(ModulePage page) {
    final terms = _normalize(
      _searchController.text,
    ).split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
    final records = page.records.where((record) {
      if (widget.module == AppModule.actividades &&
          _activityFilter != _ActivityFilter.all) {
        final completed = record.actividadData?.isCompleted ?? false;
        if (_activityFilter == _ActivityFilter.pending && completed) {
          return false;
        }
        if (_activityFilter == _ActivityFilter.completed && !completed) {
          return false;
        }
      }
      final text = _normalize(
        '${record.title} ${record.details.values.join(' ')} ${record.fieldInfo?.details.values.join(' ') ?? ''} ${record.cosechaData?.toSummaryMap().values.join(' ') ?? ''}',
      );
      return terms.every(text.contains);
    }).toList();
    final look = widget.module.look;
    final compact =
        MediaQuery.sizeOf(context).height < 520 ||
        MediaQuery.viewInsetsOf(context).bottom > 0 ||
        MediaQuery.textScalerOf(context).scale(16) > 22;

    return Column(
      children: [
        if (!_searching && !compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ModuleMark(widget.module, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.module.description,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_supportsSearch && page.records.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _searchTrigger(look),
                ],
              ],
            ),
          ),
        if (widget.module == AppModule.actividades && page.records.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in {
                      _ActivityFilter.all: 'Todas',
                      _ActivityFilter.pending: 'Pendientes',
                      _ActivityFilter.completed: 'Completadas',
                    }.entries) ...[
                      ChoiceChip(
                        label: Text(
                          entry.value,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _activityFilter == entry.key
                                ? AppTheme.ink
                                : AppTheme.inkSoft,
                          ),
                        ),
                        selected: _activityFilter == entry.key,
                        selectedColor: AppTheme.maize,
                        backgroundColor: AppTheme.surface,
                        side: const BorderSide(
                          color: AppTheme.border,
                          width: 1,
                        ),
                        onSelected: (_) =>
                            setState(() => _activityFilter = entry.key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: page.records.isEmpty
              ? AppEmptyState(
                  icon: widget.module.icon,
                  tone: look.tone,
                  ink: look.ink,
                  title: 'Todavía no hay ${widget.module.label.toLowerCase()}',
                  message:
                      '${compact ? '${widget.module.description}\n\n' : ''}La información disponible para tu cuenta aparecerá aquí. Pulsa Actualizar para volver a consultar.',
                  action: OutlinedButton.icon(
                    onPressed: () => _load(1),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualizar'),
                  ),
                )
              : records.isEmpty
              ? AppEmptyState(
                  icon: Icons.search_off_rounded,
                  tone: AppTheme.maizeSoft,
                  ink: const Color(0xFF5F4100),
                  title: 'No encontramos coincidencias',
                  message: _activityFilter != _ActivityFilter.all
                      ? 'Prueba cambiando el filtro de estado o limpiando la búsqueda.'
                      : 'Prueba con otro nombre o limpia la búsqueda.',
                  action: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _activityFilter = _ActivityFilter.all;
                      _searchController.clear();
                    }),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(
                      _activityFilter != _ActivityFilter.all &&
                              _searchController.text.isEmpty
                          ? 'Mostrar todas'
                          : 'Limpiar búsqueda',
                    ),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    4,
                    20,
                    _canCreateLote || _canAssignActividad || _canCreateCosecha
                        ? 92
                        : 20,
                  ),
                  itemCount: records.length,
                  itemBuilder: (context, index) => _recordCard(records[index]),
                ),
        ),
        if (page.lastPage > 1) _pager(page),
      ],
    );
  }

  Widget _searchTrigger(ModuleLook look) {
    return Semantics(
      button: true,
      label: 'Buscar por nombre, cultivo o persona',
      excludeSemantics: true,
      child: PressableCard(
        onTap: () => setState(() => _searching = true),
        depth: 3,
        color: Colors.white,
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 26, color: AppTheme.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Buscar por nombre, cultivo o persona',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppTheme.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pager(ModulePage page) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppTheme.surface,
      border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Página ${page.currentPage} de ${page.lastPage}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: page.currentPage > 1
                      ? () => _load(page.currentPage - 1)
                      : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Anterior'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: page.currentPage < page.lastPage
                      ? () => _load(page.currentPage + 1)
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Siguiente'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _recordCard(ModuleRecord record) {
    final look = widget.module.look;
    final info = record.fieldInfo;
    final cosecha = record.cosechaData;
    final fields = (cosecha?.toSummaryMap() ?? info?.summary ?? record.details)
        .entries
        .where((field) => field.key != 'Identificador')
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PressableCard(
        onTap: _supportsSearch ? () => _openRecord(record) : null,
        padding: EdgeInsets.zero,
        borderColor: AppTheme.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cosecha != null ? 'Cosecha #${record.id}' : record.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (info?.status != null) ...[
                    const SizedBox(height: 10),
                    RecordStatusBadge(status: info!.status!),
                  ],
                  const SizedBox(height: 14),
                  if (info != null && info.status == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: InfoLine(label: 'Estado', value: 'No disponible'),
                    ),
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InfoLine(label: field.key, value: field.value),
                    ),
                ],
              ),
            ),
            if (_supportsSearch)
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
                decoration: BoxDecoration(
                  color: look.tone,
                  border: const Border(
                    top: BorderSide(color: AppTheme.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ver detalle',
                        style: TextStyle(
                          color: look.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: look.ink,
                      size: 26,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
