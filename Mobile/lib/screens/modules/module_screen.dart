import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

class ModuleScreen extends StatefulWidget {
  const ModuleScreen({
    super.key,
    required this.module,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final AppModule module;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  late Future<ModulePage> _request = widget.service.load(
    widget.module,
    widget.user,
  );
  int _page = 1;
  final _searchController = TextEditingController();
  bool _searching = false;

  bool get _supportsSearch =>
      widget.module == AppModule.lotes ||
      widget.module == AppModule.actividades;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      final text = _normalize(
        '${record.title} ${record.details.values.join(' ')} ${record.fieldInfo?.details.values.join(' ') ?? ''}',
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
                    ModuleMark(widget.module, size: compact ? 40 : 52),
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
                if (_supportsSearch && page.records.isNotEmpty && !compact) ...[
                  const SizedBox(height: 14),
                  _searchTrigger(look),
                ],
              ],
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
                  message: 'Prueba con otro nombre o limpia la búsqueda.',
                  action: OutlinedButton.icon(
                    onPressed: _clearSearch,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Limpiar búsqueda'),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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
      border: Border(top: BorderSide(color: AppTheme.ink, width: 2)),
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
    final fields = (info?.summary ?? record.details).entries
        .where((field) => field.key != 'Identificador')
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PressableCard(
        onTap: _supportsSearch ? () => _openRecord(record) : null,
        padding: EdgeInsets.zero,
        borderColor: AppTheme.ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
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
                    top: BorderSide(color: AppTheme.ink, width: 2),
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
