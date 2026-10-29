import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
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
        '${record.title} ${record.details.values.join(' ')}',
      );
      return terms.every(text.contains);
    }).toList();

    return Column(
      children: [
        if (!_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.sage,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(widget.module.icon, color: AppTheme.forest),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.module.description,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: AppTheme.muted),
                  ),
                ),
              ],
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
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
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

  Widget _recordCard(ModuleRecord record) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _supportsSearch ? () => _openRecord(record) : null,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(record.title, style: Theme.of(context).textTheme.titleLarge),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppTheme.line),
              ),
              for (final field in record.details.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${field.key}: ${field.value}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              if (_supportsSearch) ...[
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ver detalle',
                        style: TextStyle(
                          color: AppTheme.forest,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: AppTheme.forest,
                      size: 20,
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
