import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
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
          body: SafeArea(
            child: loading
                ? const AppLoading(message: 'Cargando registros...')
                : snapshot.hasError
                ? AppErrorState(
                    message: snapshot.error is ApiException
                        ? (snapshot.error! as ApiException).message
                        : 'No se pudieron consultar los registros.',
                    onRetry: () => _load(_page),
                  )
                : _records(snapshot.data!),
          ),
        );
      },
    );
  }

  Widget _records(ModulePage page) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Consulta de registros'),
      ),
      Expanded(
        child: page.records.isEmpty
            ? const Center(child: Text('No hay registros disponibles.'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: page.records.length,
                itemBuilder: (context, index) {
                  final record = page.records[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (final field in record.details.entries)
                            Text('${field.key}: ${field.value}'),
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
