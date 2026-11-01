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

class LoteActivityHistoryScreen extends StatefulWidget {
  const LoteActivityHistoryScreen({
    super.key,
    required this.loteId,
    this.loteName,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final int loteId;
  final String? loteName;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<LoteActivityHistoryScreen> createState() =>
      _LoteActivityHistoryScreenState();
}

class _LoteActivityHistoryScreenState extends State<LoteActivityHistoryScreen> {
  int _page = 1;
  late Future<ModulePage> _request = _load();

  @override
  void didUpdateWidget(covariant LoteActivityHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loteId != widget.loteId || oldWidget.user != widget.user) {
      _page = 1;
      _request = _load();
      _request.ignore();
    }
  }

  Future<ModulePage> _load() => widget.service.loadLoteActivities(
    widget.user,
    widget.loteId,
    page: _page,
  );

  void _showPage(int page) => setState(() {
    _page = page;
    _request = _load();
    _request.ignore();
  });

  void _backToLote() {
    final navigator = Navigator.of(context);
    final detailRoute = '${AppModule.lotes.route}/${widget.loteId}';
    var found = false;
    navigator.popUntil((route) {
      found = route.settings.name == detailRoute;
      return found || route.isFirst;
    });
    if (!found) navigator.pushNamed(detailRoute);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ModulePage>(
    future: _request,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final error = snapshot.error;
      if (!loading && error is ApiException && error.statusCode == 403) {
        return ModuleAccessDenied(
          title: 'Historial de actividades',
          onRefreshPermissions: widget.onRefreshPermissions,
        );
      }
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Volver al lote',
            onPressed: _backToLote,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Historial de actividades'),
          actions: [
            IconButton(
              tooltip: 'Actualizar historial',
              onPressed: loading ? null : () => _showPage(_page),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: loading
              ? const AppLoading(message: 'Cargando historial...')
              : error is ApiException && error.statusCode == 404
              ? const AppEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'El lote ya no está disponible',
                  message: 'Vuelve a la lista de lotes para actualizarla.',
                )
              : snapshot.hasError
              ? AppErrorState(
                  message: error is ApiException
                      ? error.message
                      : 'No se pudo consultar el historial del lote.',
                  onRetry: () => _showPage(_page),
                )
              : _activities(snapshot.requireData),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: OutlinedButton.icon(
                onPressed: _backToLote,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Volver al lote'),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _activities(ModulePage page) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(
        key: ValueKey((widget.loteId, page.currentPage)),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          Text(
            'Lote #${widget.loteId}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            widget.loteName ?? 'Lote #${widget.loteId}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text('Más recientes primero, según su fecha de inicio.'),
          const SizedBox(height: 24),
          if (page.records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Este lote todavía no tiene actividades registradas.',
              ),
            ),
          for (final activity in page.records)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      color: AppTheme.forest,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Inicio: ${activity.fieldInfo?.details['Inicio'] ?? 'Sin registrar'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (page.lastPage > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: page.currentPage > 1
                      ? () => _showPage(page.currentPage - 1)
                      : null,
                  child: const Text('Anterior'),
                ),
                Text('Página ${page.currentPage} de ${page.lastPage}'),
                FilledButton(
                  onPressed: page.currentPage < page.lastPage
                      ? () => _showPage(page.currentPage + 1)
                      : null,
                  child: const Text('Siguiente'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
