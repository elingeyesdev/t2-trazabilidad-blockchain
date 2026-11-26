import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/auth_user.dart';
import '../navigation/app_module.dart';
import 'module_service.dart';
import 'offline_store.dart';

/// Avisa con una notificación del teléfono cuando aparecen actividades
/// pendientes nuevas para el usuario.
///
// shortcut: revisa al abrir la app o volver a ella; no llega con la app
// cerrada. Para eso hace falta push (Firebase + un endpoint de tokens en Laravel).
class TaskNotifier {
  TaskNotifier(this._store, [FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final OfflineStore _store;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// Ids de [current] que no estaban en [seen]. Sin historial (primera vez)
  /// no hay nada "nuevo": solo se recuerda lo que ya existe.
  static List<int> fresh(List<int>? seen, List<int> current) => seen == null
      ? const []
      : current.where((id) => !seen.contains(id)).toList();

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> check(ModuleService service, AuthUser user) async {
    try {
      if (!AppModule.actividades.canOpen(user) ||
          user.roles.contains('admin')) {
        return;
      }
      final page = await service.load(AppModule.actividades, user);
      final pending = page.records
          .where(
            (r) => r.actividadData != null && !r.actividadData!.isCompleted,
          )
          .toList();
      final key = '${user.id}';
      final news = fresh(await _store.readSeen(key), [
        for (final r in pending) r.id,
      ]);
      await _store.writeSeen(key, [for (final r in pending) r.id]);
      if (news.isEmpty) return;
      await _init();
      final first = pending.firstWhere((r) => r.id == news.first);
      await _plugin.show(
        1,
        news.length == 1
            ? 'Nueva actividad asignada'
            : '${news.length} actividades nuevas',
        news.length == 1
            ? first.title
            : '${first.title} y ${news.length - 1} más',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'tareas',
            'Tareas asignadas',
            channelDescription: 'Avisos de actividades nuevas para ti',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {
      // Un aviso nunca debe interrumpir el trabajo del usuario.
    }
  }
}
