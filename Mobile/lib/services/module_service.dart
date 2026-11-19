import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/actividad_models.dart';
import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/lote_models.dart';
import '../models/module_page.dart';
import '../navigation/app_module.dart';
import 'api_client.dart';

class ModuleService {
  const ModuleService(this._api);

  final ApiClient _api;

  Future<ModulePage> loadLoteActivities(
    AuthUser user,
    int loteId, {
    int page = 1,
  }) async {
    if (!AppModule.lotes.canOpen(user)) {
      throw const ApiException(
        'No tienes permiso para consultar este lote.',
        statusCode: 403,
      );
    }
    if (loteId <= 0 || page < 1) {
      throw const ApiException('El historial solicitado no es válido.');
    }
    final response = await _api.request(
      'GET',
      'lotes/$loteId/actividades',
      queryParameters: {
        'page': '$page',
        'sort': 'fechainicio',
        'direction': 'desc',
      },
    );
    const invalidHistory = ApiException(
      'La información recibida no corresponde al historial solicitado.',
    );
    final rows = response is Map<String, dynamic> ? response['data'] : response;
    if (rows is! List ||
        rows.any((row) {
          if (row is! Map<String, dynamic> || row['loteid'] != loteId) {
            return true;
          }
          final lot = row['lote'];
          return lot != null &&
              (lot is! Map<String, dynamic> || lot['loteid'] != loteId);
        })) {
      throw invalidHistory;
    }
    final result = ModulePage.fromJson(
      response,
      idField: AppModule.actividades.idField,
      titleField: AppModule.actividades.titleField,
      fallbackTitle: 'Actividad',
      fields: AppModule.actividades.fields,
    );
    if (result.currentPage != page) {
      throw invalidHistory;
    }
    return result;
  }

  Future<ModuleRecord> loadDetail(
    AppModule module,
    AuthUser user,
    int id,
  ) async {
    if (module != AppModule.lotes && module != AppModule.actividades) {
      throw ArgumentError(
        'El detalle está disponible para lotes y actividades.',
      );
    }
    if (!module.canOpen(user)) {
      throw const ApiException(
        'No tienes permiso para consultar este módulo.',
        statusCode: 403,
      );
    }
    if (id <= 0) {
      throw const ApiException('El registro solicitado no es válido.');
    }
    final response = await _api.request('GET', '${module.endpoint}/$id');
    final record = ModuleRecord.fromJson(
      response,
      idField: module.idField,
      titleField: module.titleField,
      fallbackTitle: module == AppModule.lotes ? 'Lote' : 'Actividad',
      fields: {
        ...module.fields,
        if (module == AppModule.lotes) ...{
          'fechasiembra': 'Fecha de siembra',
          'codigo_trazabilidad': 'Código de trazabilidad',
          'fechacreacion': 'Fecha de creación',
        },
        if (module == AppModule.actividades) ...{
          'fechafin': 'Finalización',
          'observaciones': 'Observaciones',
        },
      },
    );
    if (record.id != id) {
      throw const ApiException(
        'La información recibida no corresponde al registro solicitado.',
      );
    }
    return record;
  }

  Future<ModulePage> load(
    AppModule module,
    AuthUser user, {
    int page = 1,
  }) async {
    if (!module.canOpen(user)) {
      throw const ApiException(
        'No tienes permiso para consultar este módulo.',
        statusCode: 403,
      );
    }
    if (page < 1) {
      throw const ApiException('La página solicitada no es válida.');
    }
    final response = await _api.request(
      'GET',
      module.endpoint,
      queryParameters: {'page': '$page'},
    );
    return ModulePage.fromJson(
      response,
      idField: module.idField,
      titleField: module.titleField,
      fallbackTitle: module.label,
      fields: module.fields,
    );
  }

  static final Map<String, String> _loteDetailFields = {
    ...AppModule.lotes.fields,
    'fechasiembra': 'Fecha de siembra',
    'codigo_trazabilidad': 'Código de trazabilidad',
    'fechacreacion': 'Fecha de creación',
  };

  Future<List<SeedOption>> loadSeedOptions(AuthUser user) async {
    if (!LotePermissions.canCreate(user) &&
        !LotePermissions.canEdit(user) &&
        !user.permissions.contains(AppModule.insumos.permission)) {
      throw const ApiException(
        'No tienes permiso para consultar las semillas disponibles.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', AppModule.insumos.endpoint);
    return SeedOption.listFromJson(response);
  }

  Future<ModuleRecord> createLote(
    AuthUser user, {
    required String name,
    required int seedId,
    required double surface,
    String? location,
    double? latitude,
    double? longitude,
    double? plannedSeedAmount,
  }) async {
    if (!LotePermissions.canCreate(user)) {
      throw const ApiException(
        'No tienes permiso para crear lotes.',
        statusCode: 403,
      );
    }
    if ((latitude == null) != (longitude == null)) {
      throw const ApiException(
        'Revisa los datos enviados.',
        statusCode: 422,
        validationErrors: {
          'latitud': ['Indique ambas coordenadas o deje ambas vacías.'],
          'longitud': ['Indique ambas coordenadas o deje ambas vacías.'],
        },
      );
    }
    final cleanLocation = location?.trim();
    final body = <String, Object?>{
      'nombre': name.trim(),
      'insumosemillaid': seedId,
      'superficie': surface,
      if (cleanLocation != null && cleanLocation.isNotEmpty)
        'ubicacion': cleanLocation,
      if (latitude != null && longitude != null) ...{
        'latitud': latitude,
        'longitud': longitude,
      },
      'cantidad_semilla_planificada': ?plannedSeedAmount,
    };
    final response = await _api.request(
      'POST',
      AppModule.lotes.endpoint,
      body: body,
    );
    return ModuleRecord.fromJson(
      response,
      idField: AppModule.lotes.idField,
      titleField: AppModule.lotes.titleField,
      fallbackTitle: 'Lote',
      fields: _loteDetailFields,
    );
  }

  Future<ModuleRecord> updateLote(
    AuthUser user,
    int loteId, {
    required Map<String, Object?> changes,
  }) async {
    if (!LotePermissions.canEdit(user)) {
      throw const ApiException(
        'No tienes permiso para editar este lote.',
        statusCode: 403,
      );
    }
    if (loteId <= 0) {
      throw const ApiException('El lote solicitado no es válido.');
    }
    if (changes.isEmpty) {
      throw const ApiException('No hay cambios para guardar.');
    }
    final response = await _api.request(
      'PATCH',
      '${AppModule.lotes.endpoint}/$loteId',
      body: changes,
    );
    final record = ModuleRecord.fromJson(
      response,
      idField: AppModule.lotes.idField,
      titleField: AppModule.lotes.titleField,
      fallbackTitle: 'Lote',
      fields: _loteDetailFields,
    );
    if (record.id != loteId) {
      throw const ApiException(
        'La información recibida no corresponde al lote editado.',
      );
    }
    return record;
  }

  static final Map<String, String> _actividadDetailFields = {
    ...AppModule.actividades.fields,
    'fechafin': 'Finalización',
    'observaciones': 'Observaciones',
  };

  Future<List<ActividadTipoOption>> loadActividadTipos(AuthUser user) async {
    if (!ActividadPermissions.canAssign(user) &&
        !user.permissions.contains('catalogos.view')) {
      throw const ApiException(
        'No tienes permiso para consultar los tipos de actividad.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', 'tipoactividades');
    return ActividadTipoOption.listFromJson(response);
  }

  Future<List<PrioridadOption>> loadPrioridades(AuthUser user) async {
    if (!ActividadPermissions.canAssign(user) &&
        !user.permissions.contains('catalogos.view')) {
      throw const ApiException(
        'No tienes permiso para consultar las prioridades.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', 'prioridades');
    return PrioridadOption.listFromJson(response);
  }

  Future<List<LoteOption>> loadLoteOptions(AuthUser user) async {
    if (!AppModule.lotes.canOpen(user)) {
      throw const ApiException(
        'No tienes permiso para consultar los lotes.',
        statusCode: 403,
      );
    }
    final page = await load(AppModule.lotes, user);
    return page.records
        .where((record) => record.loteData?.isClosed != true)
        .map(
          (record) => LoteOption(
            id: record.id,
            name: record.title,
            cropName: record.fieldInfo?.details['Cultivo'],
          ),
        )
        .toList();
  }

  Future<List<ResponsableOption>> loadResponsables(AuthUser user) async {
    if (!ActividadPermissions.canAssign(user)) {
      throw const ApiException(
        'No tienes permiso para consultar los responsables.',
        statusCode: 403,
      );
    }
    final byId = <int, ResponsableOption>{
      user.id: ResponsableOption(
        id: user.id,
        name: user.fullName,
        roleLabel: 'Yo (Jefe agrícola)',
      ),
    };
    try {
      final response = await _api.request('GET', AppModule.usuarios.endpoint);
      for (final item in ResponsableOption.listFromUsersJson(response)) {
        if (item.id == user.id) continue;
        byId[item.id] = item;
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) rethrow;
    }
    return byId.values.toList();
  }

  Future<ModuleRecord> createActividad(
    AuthUser user, {
    required int loteId,
    required int responsableId,
    required int tipoActividadId,
    int? prioridadId,
    String? description,
    String? plannedDate,
    String? observations,
    String? detailJson,
  }) async {
    if (!ActividadPermissions.canAssign(user)) {
      throw const ApiException(
        'Solo el jefe agrícola autorizado puede asignar actividades.',
        statusCode: 403,
      );
    }
    final cleanDescription = description?.trim();
    final cleanPlannedDate = plannedDate?.trim();
    final cleanObservations = observations?.trim();
    final cleanDetail = detailJson?.trim();
    final body = <String, Object?>{
      'loteid': loteId,
      'usuarioid': responsableId,
      'tipoactividadid': tipoActividadId,
      'prioridadid': ?prioridadId,
      if (cleanDescription != null && cleanDescription.isNotEmpty)
        'descripcion': cleanDescription,
      if (cleanPlannedDate != null && cleanPlannedDate.isNotEmpty)
        'fecha_planificada': cleanPlannedDate,
      if (cleanObservations != null && cleanObservations.isNotEmpty)
        'observaciones': cleanObservations,
      if (cleanDetail != null && cleanDetail.isNotEmpty)
        'detalle_actividad_json': cleanDetail,
    };
    final response = await _api.request(
      'POST',
      AppModule.actividades.endpoint,
      body: body,
    );
    return ModuleRecord.fromJson(
      response,
      idField: AppModule.actividades.idField,
      titleField: AppModule.actividades.titleField,
      fallbackTitle: 'Actividad',
      fields: _actividadDetailFields,
    );
  }

  Future<ModuleRecord> updateActividadObservaciones(
    AuthUser user,
    int actividadId, {
    required String? observations,
  }) async {
    if (!ActividadPermissions.canAddObservations(user)) {
      throw const ApiException(
        'No tienes permiso para actualizar observaciones.',
        statusCode: 403,
      );
    }
    if (actividadId <= 0) {
      throw const ApiException('La actividad solicitada no es válida.');
    }
    final clean = observations?.trim();
    final response = await _api.request(
      'PATCH',
      '${AppModule.actividades.endpoint}/$actividadId',
      body: {'observaciones': (clean == null || clean.isEmpty) ? null : clean},
    );
    final record = ModuleRecord.fromJson(
      response,
      idField: AppModule.actividades.idField,
      titleField: AppModule.actividades.titleField,
      fallbackTitle: 'Actividad',
      fields: _actividadDetailFields,
    );
    if (record.id != actividadId) {
      throw const ApiException(
        'La información recibida no corresponde a la actividad editada.',
      );
    }
    return record;
  }

  Future<ModuleRecord> closeActividad(
    AuthUser user,
    int actividadId, {
    required String result,
    required EvidencePhoto photo,
    List<Map<String, Object?>> consumos = const [],
  }) async {
    if (!user.permissions.contains(AppModule.actividades.permission) ||
        user.roles.contains('admin') ||
        user.roles.contains('jefe_agricultor')) {
      throw const ApiException(
        'No tienes permiso para cerrar esta actividad.',
        statusCode: 403,
      );
    }
    if (actividadId <= 0) {
      throw const ApiException('La actividad solicitada no es válida.');
    }
    final fields = <String, String>{'resultado': result.trim()};
    for (var i = 0; i < consumos.length; i++) {
      final item = consumos[i];
      for (final entry in item.entries) {
        if (entry.value != null) {
          fields['consumos[$i][${entry.key}]'] = entry.value.toString();
        }
      }
    }
    final response = await _api.request(
      'POST',
      '${AppModule.actividades.endpoint}/$actividadId/cerrar',
      fields: fields,
      files: [
        http.MultipartFile.fromBytes(
          'evidencia_foto',
          photo.bytes,
          filename: photo.filename,
          contentType: http.MediaType.parse(photo.contentType),
        ),
      ],
    );
    final record = ModuleRecord.fromJson(
      response,
      idField: AppModule.actividades.idField,
      titleField: AppModule.actividades.titleField,
      fallbackTitle: 'Actividad',
      fields: _actividadDetailFields,
    );
    if (record.id != actividadId) {
      throw const ApiException(
        'La información recibida no corresponde a la actividad cerrada.',
      );
    }
    return record;
  }

  Future<List<AlmacenOption>> loadAlmacenOptions(AuthUser user) async {
    if (!user.permissions.contains(AppModule.almacenes.permission)) {
      throw const ApiException(
        'No tienes permiso para consultar los almacenes autorizados.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', AppModule.almacenes.endpoint);
    return AlmacenOption.listFromJson(response);
  }

  Future<List<InsumoOption>> loadInsumoOptions(AuthUser user) async {
    if (!user.permissions.contains(AppModule.insumos.permission)) {
      throw const ApiException(
        'No tienes permiso para consultar los insumos disponibles.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', AppModule.insumos.endpoint);
    return InsumoOption.listFromJson(response);
  }

  Future<Uint8List> loadActividadEvidence(
    AuthUser user,
    int actividadId,
  ) async {
    if (!AppModule.actividades.canOpen(user)) {
      throw const ApiException(
        'No tienes permiso para consultar esta fotografía.',
        statusCode: 403,
      );
    }
    if (actividadId <= 0) {
      throw const ApiException('La actividad solicitada no es válida.');
    }
    return _api.getBytes(
      '${AppModule.actividades.endpoint}/$actividadId/evidencia',
    );
  }
}
