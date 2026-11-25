import 'package:flutter/material.dart';

import '../models/auth_user.dart';
import '../models/module_page.dart';
import '../navigation/app_module.dart';
import '../services/module_service.dart';
import '../theme/app_theme.dart';
import 'field_kit.dart';
import 'motion.dart';

/// Las actividades pendientes del usuario, al abrir la app. Si no hay
/// actividades, no carga o el usuario no tiene el módulo, no ocupa lugar.
class TodayTasks extends StatefulWidget {
  const TodayTasks({
    super.key,
    required this.user,
    required this.service,
    required this.onOpen,
  });

  final AuthUser user;
  final ModuleService service;
  final void Function(AppModule module, int id) onOpen;

  @override
  State<TodayTasks> createState() => _TodayTasksState();
}

class _TodayTasksState extends State<TodayTasks> {
  static const _max = 3;
  Future<ModulePage>? _request;

  @override
  void initState() {
    super.initState();
    // El administrador supervisa, no ejecuta: sus actividades no son "tareas".
    if (AppModule.actividades.canOpen(widget.user) &&
        !widget.user.roles.contains('admin')) {
      _request = widget.service.load(AppModule.actividades, widget.user)
        ..ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_request == null) return const SizedBox.shrink();
    return FutureBuilder<ModulePage>(
      future: _request,
      builder: (context, snapshot) {
        final pending = (snapshot.data?.records ?? const <ModuleRecord>[])
            .where(
              (r) => r.actividadData != null && !r.actividadData!.isCompleted,
            )
            .toList();
        if (pending.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                pending.length == 1
                    ? 'Te toca 1 actividad'
                    : 'Te tocan ${pending.length} actividades',
                color: AppTheme.maize,
              ),
              const SizedBox(height: 14),
              for (final (i, task) in pending.take(_max).indexed) ...[
                FadeSlideIn(
                  index: i,
                  child: PressableCard(
                    onTap: () => widget.onOpen(AppModule.actividades, task.id),
                    padding: EdgeInsets.zero,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: AppTheme.maize, width: 6),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(task.title, style: theme.titleMedium),
                                  if (task.actividadData?.loteName != null)
                                    Text(
                                      task.actividadData!.loteName!,
                                      style: theme.bodyMedium,
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (pending.length > _max)
                Text(
                  'y ${pending.length - _max} más en Actividades',
                  style: theme.bodyMedium,
                ),
            ],
          ),
        );
      },
    );
  }
}
