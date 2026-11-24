import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/actividad_models.dart';
import '../models/api_exception.dart';
import '../models/auth_user.dart';
import 'module_service.dart';
import 'offline_store.dart';

/// Resultado que un formulario devuelve cuando no hubo señal y el registro
/// quedó guardado en el teléfono para enviarse después.
class QueuedResult {
  const QueuedResult(this.message);
  final String message;
}

enum PendingKind { cosecha, cierre }

class PendingItem {
  PendingItem({
    required this.id,
    required this.userId,
    required this.kind,
    required this.label,
    required this.payload,
    this.error,
  });

  final String id;
  final int userId;
  final PendingKind kind;
  final String label;
  final Map<String, dynamic> payload;

  /// Motivo por el que el servidor rechazó el registro. Sin error, está en espera.
  String? error;

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'kind': kind.name,
    'label': label,
    'payload': payload,
    'error': error,
  };

  static PendingItem? fromJson(Map<String, dynamic> json) {
    final kind = PendingKind.values.asNameMap()[json['kind']];
    final payload = json['payload'];
    if (kind == null ||
        json['id'] is! String ||
        json['userId'] is! int ||
        payload is! Map<String, dynamic>) {
      return null;
    }
    return PendingItem(
      id: json['id'] as String,
      userId: json['userId'] as int,
      kind: kind,
      label: json['label'] as String? ?? 'Registro',
      payload: payload,
      error: json['error'] as String?,
    );
  }
}

/// Registros hechos sin señal (cosechas y cierres de actividad) que esperan
/// para enviarse. Lo creado en el servidor sigue siendo la fuente de verdad:
/// aquí solo se guarda lo que el usuario ya confirmó.
///
// shortcut: se reintenta al abrir la app, al volver a primer plano o con el
// botón "Enviar ahora"; sin detector de red. Súbelo a connectivity_plus si
// hace falta enviar en el momento exacto en que vuelve la señal.
class PendingQueue extends ChangeNotifier {
  PendingQueue(this._store);

  final OfflineStore _store;
  List<PendingItem> _items = [];
  bool _syncing = false;

  bool get syncing => _syncing;

  List<PendingItem> forUser(AuthUser user) =>
      _items.where((item) => item.userId == user.id).toList(growable: false);

  Future<void> load() async {
    _items = (await _store.readQueue())
        .map(PendingItem.fromJson)
        .whereType<PendingItem>()
        .toList();
    notifyListeners();
  }

  Future<void> _save() =>
      _store.writeQueue([for (final item in _items) item.toJson()]);

  Future<void> _add(PendingItem item) async {
    _items.add(item);
    await _save();
    notifyListeners();
  }

  Future<void> addCosecha(
    AuthUser user, {
    required String label,
    required int loteId,
    required String cantidad,
    required int unidadMedidaId,
    int? catalogoTamanoConteoId,
    String? fechaCosecha,
    String? observaciones,
  }) => _add(
    PendingItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: user.id,
      kind: PendingKind.cosecha,
      label: label,
      payload: {
        'loteId': loteId,
        'cantidad': cantidad,
        'unidadMedidaId': unidadMedidaId,
        'catalogoTamanoConteoId': catalogoTamanoConteoId,
        'fechaCosecha': fechaCosecha,
        'observaciones': observaciones,
      },
    ),
  );

  Future<void> addCierre(
    AuthUser user, {
    required String label,
    required int actividadId,
    required String result,
    required EvidencePhoto photo,
    required List<Map<String, Object?>> consumos,
  }) => _add(
    PendingItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: user.id,
      kind: PendingKind.cierre,
      label: label,
      payload: {
        'actividadId': actividadId,
        'result': result,
        'consumos': consumos,
        'photoName': photo.originalName,
        'photo': base64Encode(photo.bytes),
      },
    ),
  );

  Future<void> discard(PendingItem item) async {
    _items.removeWhere((other) => other.id == item.id);
    await _save();
    notifyListeners();
  }

  /// Envía en orden lo pendiente del usuario. Se detiene al primer corte de
  /// señal; lo que el servidor rechaza queda marcado con su motivo.
  /// Devuelve cuántos registros se enviaron.
  Future<int> flush(ModuleService service, AuthUser user) async {
    if (_syncing) return 0;
    _syncing = true;
    notifyListeners();
    var sent = 0;
    try {
      for (final item in forUser(user)) {
        if (item.error != null) continue;
        try {
          await _send(service, user, item);
          _items.removeWhere((other) => other.id == item.id);
          sent++;
        } on ApiException catch (error) {
          if (error.offline || (error.statusCode ?? 0) >= 500) break;
          item.error = error.validationErrors.values
              .expand((messages) => messages)
              .followedBy([error.message])
              .first;
        }
        await _save();
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
    return sent;
  }

  Future<void> _send(ModuleService service, AuthUser user, PendingItem item) {
    final p = item.payload;
    return switch (item.kind) {
      PendingKind.cosecha => service.createCosecha(
        user,
        loteId: p['loteId'] as int,
        cantidad: p['cantidad'] as String,
        unidadMedidaId: p['unidadMedidaId'] as int,
        catalogoTamanoConteoId: p['catalogoTamanoConteoId'] as int?,
        fechaCosecha: p['fechaCosecha'] as String?,
        observaciones: p['observaciones'] as String?,
      ),
      PendingKind.cierre => service.closeActividad(
        user,
        p['actividadId'] as int,
        result: p['result'] as String,
        photo: EvidencePhoto(
          base64Decode(p['photo'] as String),
          name: p['photoName'] as String,
        ),
        consumos: (p['consumos'] as List).cast<Map<String, Object?>>(),
      ),
    };
  }
}
