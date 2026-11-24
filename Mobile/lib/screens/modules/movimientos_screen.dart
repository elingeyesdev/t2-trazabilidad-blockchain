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
import '../../widgets/movimiento_tile.dart';
import 'module_access_denied.dart';

/// Historial de entradas y salidas de todos los almacenes del usuario, por día.
class MovimientosScreen extends StatefulWidget {
  const MovimientosScreen({
    super.key,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<MovimientosScreen> createState() => _MovimientosScreenState();
}

class _MovimientosScreenState extends State<MovimientosScreen> {
  static const _filters = <String?, String>{
    null: 'Todos',
    'ingreso': 'Entradas',
    'salida': 'Salidas',
  };

  String? _naturaleza;
  int _page = 1;
  late Future<InventarioMovimientosPage> _request = _fetch();

  Future<InventarioMovimientosPage> _fetch() => widget.service.loadMovimientos(
    widget.user,
    naturaleza: _naturaleza,
    page: _page,
  );

  void _reload({String? naturaleza, int? page, bool keepFilter = true}) {
    setState(() {
      if (!keepFilter) _naturaleza = naturaleza;
      _page = page ?? 1;
      _request = _fetch();
      _request.ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InventarioMovimientosPage>(
      future: _request,
      builder: (context, snapshot) {
        final error = snapshot.error;
        if (error is ApiException && error.statusCode == 403) {
          return ModuleAccessDenied(
            title: AppModule.movimientos.label,
            onRefreshPermissions: widget.onRefreshPermissions,
          );
        }
        final loading = snapshot.connectionState != ConnectionState.done;
        return Scaffold(
          appBar: AppBar(
            title: Text(AppModule.movimientos.label),
            actions: [
              IconButton(
                tooltip: 'Actualizar movimientos',
                onPressed: loading ? null : () => _reload(page: _page),
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _filterBar(loading),
                Expanded(child: _body(snapshot, loading)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filterBar(bool loading) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in _filters.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: _naturaleza == entry.key,
              selectedColor: AppTheme.sprout,
              backgroundColor: AppTheme.surface,
              side: BorderSide(
                color: _naturaleza == entry.key
                    ? AppTheme.field
                    : AppTheme.border,
              ),
              onSelected: loading
                  ? null
                  : (_) => _reload(naturaleza: entry.key, keepFilter: false),
            ),
        ],
      ),
    ),
  );

  Widget _body(
    AsyncSnapshot<InventarioMovimientosPage> snapshot,
    bool loading,
  ) {
    if (loading) {
      return const AppLoading(
        message: 'Cargando movimientos...',
        shape: LoadingShape.list,
      );
    }
    if (snapshot.hasError) {
      final error = snapshot.error;
      return AppErrorState(
        message: error is ApiException
            ? error.message
            : 'No se pudieron cargar los movimientos.',
        onRetry: () => _reload(page: _page),
      );
    }
    final page = snapshot.requireData;
    if (page.items.isEmpty) {
      return AppEmptyState(
        icon: Icons.swap_horiz_rounded,
        title: 'Sin movimientos',
        message: _naturaleza == null
            ? 'Cuando se registre una entrada o salida de productos, aparecerá aquí.'
            : 'No hay ${_filters[_naturaleza]!.toLowerCase()} para mostrar.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        ...movimientoGroups(context, page.items, showAlmacen: true),
        if (page.lastPage > 1) _pager(page),
      ],
    );
  }

  Widget _pager(InventarioMovimientosPage page) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: page.currentPage > 1
                ? () => _reload(page: page.currentPage - 1)
                : null,
            child: const Text('Anteriores'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('${page.currentPage} de ${page.lastPage}'),
        ),
        Expanded(
          child: FilledButton(
            onPressed: page.currentPage < page.lastPage
                ? () => _reload(page: page.currentPage + 1)
                : null,
            child: const Text('Siguientes'),
          ),
        ),
      ],
    ),
  );
}
