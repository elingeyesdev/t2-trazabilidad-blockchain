import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/actividad_models.dart';
import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/lote_models.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/record_status_badge.dart';
import 'actividad_form_screen.dart';
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
  });

  final AppModule module;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final ValueListenable<int>? loteUpdates;
  final ValueListenable<int>? actividadUpdates;

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
      widget.module == AppModule.actividades;

  bool get _canCreateLote =>
      widget.module == AppModule.lotes &&
      LotePermissions.canCreate(widget.user);

  bool get _canAssignActividad =>
      widget.module == AppModule.actividades &&
      ActividadPermissions.canAssign(widget.user);

  @override
  void initState() {
    super.initState();
    widget.loteUpdates?.addListener(_onLoteUpdated);
    widget.actividadUpdates?.addListener(_onActividadUpdated);
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
  }

  @override
  void dispose() {
    widget.loteUpdates?.removeListener(_onLoteUpdated);
    widget.actividadUpdates?.removeListener(_onActividadUpdated);
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
    Navigator.of(context).pushNamed('${widget.module.route}/${record.id}');
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
                        : () {
                            setState(() {
                              _searching = true;
                            });
                          },
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
            body: SafeArea(child: _content(snapshot)),
            floatingActionButton:
                (_canCreateLote || _canAssignActividad) &&
                    !loading &&
                    !snapshot.hasError
                ? FloatingActionButton.extended(
                    heroTag: null,
                    backgroundColor: AppTheme.forest,
                    foregroundColor: Colors.white,
                    onPressed: _canCreateLote ? _createLote : _assignActividad,
                    icon: Icon(
                      _canCreateLote
                          ? Icons.add_rounded
                          : Icons.assignment_add,
                    ),
                    label: Text(
                      _canCreateLote ? 'Nuevo lote' : 'Asignar actividad',
                    ),
                  )
                : null,
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
        '${record.title} ${record.details.values.join(' ')} ${record.fieldInfo?.details.values.join(' ') ?? ''}',
      );
      return terms.every(text.contains);
    }).toList();

    return Column(
      children: [
        if (widget.module == AppModule.actividades && page.records.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    _ActivityFilter.all: 'Todas',
                    _ActivityFilter.pending: 'Pendientes',
                    _ActivityFilter.completed: 'Completadas',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _activityFilter == entry.key,
                      onSelected: (_) =>
                          setState(() => _activityFilter = entry.key),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: page.records.isEmpty
              ? AppEmptyState(
                  icon: widget.module.icon,
                  title: 'Todavía no hay ${widget.module.label.toLowerCase()}',
                  message:
                      'La información disponible para tu cuenta aparecerá aquí. Pulsa Actualizar para volver a consultar.',
                  action: OutlinedButton.icon(
                    onPressed: () => _load(1),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualizar'),
                  ),
                )
              : records.isEmpty
              ? AppEmptyState(
                  icon: Icons.search_off_rounded,
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
                    24,
                    8,
                    24,
                    (_canCreateLote || _canAssignActividad) ? 88 : 16,
                  ),
                  itemCount: records.length,
                  itemBuilder: (context, index) => _recordCard(records[index]),
                ),
        ),
        if (page.lastPage > 1)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: page.currentPage > 1
                      ? () => _load(page.currentPage - 1)
                      : null,
                  child: const Text('Anterior'),
                ),
                Text('Página ${page.currentPage} de ${page.lastPage}'),
                TextButton(
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

  Widget _recordCard(ModuleRecord record) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _supportsSearch ? () => _openRecord(record) : null,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    '#${record.id.toString().padLeft(3, '0')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (record.fieldInfo?.status case final status?)
                    RecordStatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 12),
              Text(record.title, style: Theme.of(context).textTheme.titleLarge),
              const Divider(height: 32, color: AppTheme.line),
              if (record.fieldInfo != null && record.fieldInfo!.status == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Estado: No disponible'),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final paired =
                      constraints.maxWidth >= 280 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 24;
                  return Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      for (final field
                          in (record.fieldInfo?.summary ?? record.details)
                              .entries)
                        SizedBox(
                          width: paired
                              ? (constraints.maxWidth - 20) / 2
                              : constraints.maxWidth,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${field.key}: ',
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                TextSpan(text: field.value),
                              ],
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: AppTheme.ink,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (_supportsSearch) ...[
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ver detalle',
                        style: TextStyle(
                          color: AppTheme.forest,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: AppTheme.forest,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
