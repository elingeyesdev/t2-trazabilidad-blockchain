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

  void _load(int page) {
    setState(() {
      _page = page;
      _request = widget.service.load(widget.module, widget.user, page: page);
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
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.module.label),
            actions: [
              IconButton(
                onPressed: loading ? null : () => _load(1),
                tooltip: 'Actualizar lista',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(child: _content(snapshot)),
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

  Widget _records(ModulePage page) => Column(
    children: [
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
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                itemCount: page.records.length,
                itemBuilder: (context, index) {
                  final record = page.records[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.line),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
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
                        ],
                      ),
                    ),
                  );
                },
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
