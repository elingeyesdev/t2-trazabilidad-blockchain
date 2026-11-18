// Modo demostración: ejecuta la app con datos de ejemplo, sin servidor.
//
//   flutter run -t tool/preview/main_preview.dart
//
// Cualquier correo y contraseña inician sesión. Sirve para revisar la
// interfaz en un teléfono o emulador sin levantar Laravel.
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _profile = {
  'usuarioid': 1,
  'nombre': 'Carmen',
  'apellido': 'Lima Quispe',
  'nombreusuario': 'carmen.lima',
  'telefono': '70012345',
  'ci_nit': '6543210 LP',
  'email': 'carmen@agrofusion.bo',
  'activo': true,
  'estado_cuenta': 'aprobado',
  'fecharegistro': '2025-03-10T10:00:00Z',
  'fechamodificacion': '2026-10-02T15:20:00Z',
  'ultimologin': '2026-11-16T07:45:00Z',
  'roles': [
    {'name': 'agricultor'},
  ],
  'permissions': [
    'lotes.view',
    'inventario.view',
    'almacen.movimientos.view',
    'certificaciones.view',
  ],
  'profile_capabilities': {'update_username': true, 'update_photo': true},
};

Map<String, Object?> _lot(
  int id,
  String name,
  String crop,
  String state,
  String place,
  num area,
  String sown,
) => {
  'loteid': id,
  'nombre': name,
  'insumo_semilla': {'nombre': crop},
  'estado_tipo': {'nombre': state},
  'usuario': {'nombre': 'Carmen', 'apellido': 'Lima'},
  'ubicacion': place,
  'superficie': area,
  'fechasiembra': sown,
  'codigo_trazabilidad': 'AF-${id.toString().padLeft(3, '0')}',
  'fechacreacion': '2026-08-01T09:30:00Z',
  'actividades_pendientes': id % 3,
};

final _lots = [
  _lot(
    7,
    'Parcela Los Pinos',
    'Maíz amarillo',
    'sembrado',
    'Sector alto',
    3.5,
    '2026-10-20',
  ),
  _lot(
    8,
    'El Bajío',
    'Papa huaycha',
    'en crecimiento',
    'Orilla del río',
    1.2,
    '2026-09-02',
  ),
  _lot(
    9,
    'Lote Santa Rosa',
    'Quinua real',
    'planificación',
    'Ladera norte',
    0.8,
    '2026-11-30',
  ),
  _lot(
    10,
    'La Esperanza',
    'Haba',
    'cosechado',
    'Camino a Achocalla',
    2,
    '2026-05-14',
  ),
];

Map<String, Object?> _activity(
  int id,
  String text,
  int lotId,
  String type,
  String planned,
  String? start,
  String? end, [
  String? notes,
]) {
  final lot = _lots.firstWhere((l) => l['loteid'] == lotId);
  return {
    'actividadid': id,
    'descripcion': text,
    'loteid': lotId,
    'lote': {
      'loteid': lotId,
      'nombre': lot['nombre'],
      'insumo_semilla': lot['insumo_semilla'],
    },
    'usuario': {'nombre': 'Carmen', 'apellido': 'Lima'},
    'tipo_actividad': {'nombre': type},
    'prioridad': {'nombre': id.isEven ? 'Alta' : 'Normal'},
    'fecha_planificada': planned,
    'fechainicio': start,
    'fechafin': end,
    'observaciones': notes,
  };
}

final _activities = [
  _activity(
    11,
    'Riego de Los Pinos',
    7,
    'Riego',
    '2026-11-18',
    '2026-11-16T07:00:00Z',
    null,
    'Revisar los surcos del sector norte.',
  ),
  _activity(
    12,
    'Fumigación preventiva',
    8,
    'Fumigación',
    '2026-11-19',
    null,
    null,
  ),
  _activity(
    13,
    'Siembra terminada',
    7,
    'Siembra',
    '2026-10-20',
    '2026-10-20T06:30:00Z',
    '2026-10-20T17:00:00Z',
    'Semilla certificada.',
  ),
  _activity(
    14,
    'Aporque de papa',
    8,
    'Labranza',
    '2026-10-05',
    '2026-10-05T08:00:00Z',
    '2026-10-06T12:00:00Z',
  ),
];

Object? _route(http.Request request) {
  final path = request.url.path.replaceFirst('/api/', '');
  final segments = path.split('/');
  switch (segments) {
    case ['login']:
      return {'token': '1|demo', 'user': _profile};
    case ['me']:
      return _profile;
    case ['logout']:
      return {'message': 'Sesión cerrada correctamente.'};
    case ['lotes']:
      return _lots;
    case ['lotes', final id]:
      final lot = _lots.firstWhere((l) => '${l['loteid']}' == id);
      return lot;
    case ['lotes', final id, 'actividades']:
      return {
        'data': [
          for (final a in _activities)
            if ('${a['loteid']}' == id) a,
        ],
        'current_page': 1,
        'last_page': 1,
      };
    case ['actividades']:
      return _activities;
    case ['actividades', final id]:
      return _activities.firstWhere((a) => '${a['actividadid']}' == id);
    case ['insumos']:
      return [
        {
          'insumoid': 1,
          'nombre': 'Semilla de maíz',
          'stock': 120,
          'descripcion': 'Bolsas de 25 kg',
        },
        {
          'insumoid': 2,
          'nombre': 'Abono orgánico',
          'stock': 40,
          'descripcion': 'Sacos',
        },
      ];
    case ['almacenes']:
      return [
        {
          'almacenid': 1,
          'nombre': 'Depósito central',
          'ubicacion': 'Patio',
          'capacidad': 500,
        },
      ];
    default:
      return <Object>[];
  }
}

class _DemoSessionStorage extends SessionStorage {
  const _DemoSessionStorage();
  static String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> clearToken() async => _token = null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const storage = _DemoSessionStorage();
  final api = ApiClient(
    config: ApiConfig(baseUrl: 'https://demo.agrofusion.local/api'),
    sessionStorage: storage,
    client: MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return http.Response(
        jsonEncode(_route(request)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  runApp(AgroFusionApp(apiClient: api, sessionStorage: storage));
}
