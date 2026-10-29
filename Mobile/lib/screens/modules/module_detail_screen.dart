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

class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({
    super.key,
    required this.module,
    required this.recordId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final AppModule module;
  final int recordId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  late Future<ModuleRecord> _request = _load();
  bool get _isLote => widget.module == AppModule.lotes;

  Future<ModuleRecord> _load() =>
      widget.service.loadDetail(widget.module, widget.user, widget.recordId);

  void _refresh() => setState(() {
    _request = _load();
    _request.ignore();
  });

  void _backToList() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(widget.module.route);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ModuleRecord>(
    future: _request,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final error = snapshot.error;
      if (!loading && error is ApiException && error.statusCode == 403) {
        return ModuleAccessDenied(
          title: _isLote ? 'Detalle del lote' : 'Detalle de actividad',
          onRefreshPermissions: widget.onRefreshPermissions,
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(_isLote ? 'Detalle del lote' : 'Detalle de actividad'),
          actions: [
            IconButton(
              tooltip: 'Actualizar detalle',
              onPressed: loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: loading
              ? const AppLoading(message: 'Cargando detalle...')
              : error is ApiException && error.statusCode == 404
              ? AppEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'El registro ya no está disponible',
                  message: 'Vuelve a la lista y actualiza la información.',
                  action: OutlinedButton.icon(
                    onPressed: _backToList,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Volver a la lista'),
                  ),
                )
              : snapshot.hasError
              ? AppErrorState(
                  message: error is ApiException
                      ? error.message
                      : 'No se pudo consultar la información.',
                  onRetry: _refresh,
                )
              : _details(snapshot.requireData),
        ),
      );
    },
  );

  Widget _details(ModuleRecord record) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.forest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(widget.module.icon, size: 32, color: AppTheme.ochre),
                  const SizedBox(height: 20),
                  Text(
                    record.title,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_isLote ? 'Lote' : 'Actividad'} #${record.id}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _isLote ? 'Información del lote' : 'Información de la actividad',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.line),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final field in record.details.entries.where(
                    (field) => field.key != 'Identificador',
                  ))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field.key,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _displayValue(field),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  String _displayValue(MapEntry<String, String> field) {
    if (field.key == 'Superficie') {
      final area = num.tryParse(field.value);
      if (area != null && area.isFinite) {
        return '${area.toStringAsFixed(2).replaceAll('.', ',')} ${area == 1 ? 'hectárea' : 'hectáreas'}';
      }
    }
    const calendarDates = {'Fecha planificada', 'Fecha de siembra'};
    const timestamps = {'Inicio', 'Finalización', 'Fecha de creación'};
    if (calendarDates.contains(field.key) || timestamps.contains(field.key)) {
      final parsed = DateTime.tryParse(field.value);
      if (parsed != null) {
        final date = timestamps.contains(field.key) ? parsed.toLocal() : parsed;
        String two(int n) => n.toString().padLeft(2, '0');
        final day = '${two(date.day)}/${two(date.month)}/${date.year}';
        return timestamps.contains(field.key) && field.value.length > 10
            ? '$day · ${two(date.hour)}:${two(date.minute)}'
            : day;
      }
    }
    return field.value;
  }
}
