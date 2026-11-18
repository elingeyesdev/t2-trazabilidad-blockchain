import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/activity_history_card.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
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
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: loading
              ? const AppLoading(message: 'Cargando historial...')
              : error is ApiException && error.statusCode == 404
              ? const AppEmptyState(
                  icon: Icons.search_off_rounded,
                  tone: AppTheme.maizeSoft,
                  ink: Color(0xFF5F4100),
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
        bottomNavigationBar: BottomActionBar(
          child: OutlinedButton.icon(
            onPressed: _backToLote,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Volver al lote'),
          ),
        ),
      );
    },
  );

  Widget _activities(ModulePage page) {
    if (page.records.isEmpty) {
      final firstPage = page.currentPage == 1;
      return Semantics(
        liveRegion: true,
        child: AppEmptyState(
          icon: Icons.event_note_rounded,
          tone: AppTheme.maizeSoft,
          ink: const Color(0xFF5F4100),
          title: firstPage
              ? 'No hay actividades para mostrar'
              : 'Esta página no tiene actividades',
          message:
              '${widget.loteName ?? 'Lote'} · #${widget.loteId}\n\n'
              '${firstPage ? 'Cuando haya actividades disponibles para consultar, aparecerán aquí.' : 'Vuelve a la primera página para consultar el historial actualizado.'}',
          action: FilledButton.icon(
            onPressed: () => _showPage(1),
            icon: Icon(
              firstPage ? Icons.refresh_rounded : Icons.first_page_rounded,
            ),
            label: Text(
              firstPage ? 'Actualizar historial' : 'Volver a la primera página',
            ),
          ),
        ),
      );
    }
    final look = AppModule.lotes.look;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          key: ValueKey((widget.loteId, page.currentPage)),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 48),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: look.tone,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.ink, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ModuleMark(AppModule.lotes, size: 36, solid: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Lote #${widget.loteId}',
                          style: TextStyle(
                            color: look.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    header: true,
                    child: Text(
                      widget.loteName ?? 'Lote #${widget.loteId}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sort_rounded, size: 18, color: look.ink),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Más recientes primero, según su fecha de inicio.',
                          style: TextStyle(
                            color: look.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final activity in page.records)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ActivityHistoryCard(activity: activity),
              ),
            if (page.lastPage > 1) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: page.currentPage > 1
                        ? () => _showPage(page.currentPage - 1)
                        : null,
                    child: const Text('Anterior'),
                  ),
                  Text(
                    'Página ${page.currentPage} de ${page.lastPage}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
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
}
