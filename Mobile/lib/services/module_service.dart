import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/actividad_models.dart';
import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/cosecha_models.dart';
import '../models/entrega_models.dart';
import '../models/inventario_models.dart';
import '../models/lote_models.dart';
import '../models/module_page.dart';
import '../models/pedido_models.dart';
import '../models/planta_models.dart';
import '../models/qr_envio_models.dart';
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
    if (module != AppModule.lotes &&
        module != AppModule.actividades &&
        module != AppModule.producciones) {
      throw ArgumentError(
        'El detalle está disponible para lotes, actividades y cosechas.',
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
    final fallbackTitle = switch (module) {
      AppModule.lotes => 'Lote',
      AppModule.actividades => 'Actividad',
      AppModule.producciones => 'Cosecha',
      _ => module.label,
    };
    final record = ModuleRecord.fromJson(
      response,
      idField: module.idField,
      titleField: module.titleField,
      fallbackTitle: fallbackTitle,
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

  Future<List<CosechaUnidadOption>> loadCosechaUnidades(AuthUser user) async {
    if (!CosechaPermissions.canCreate(user) &&
        !user.permissions.contains('catalogos.view')) {
      throw const ApiException(
        'No tienes permiso para consultar las unidades de medida.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', 'unidadesmedida');
    return CosechaUnidadOption.listFromJson(response);
  }

  Future<CosechaConfiguracion> loadCosechaConfiguracion(
    AuthUser user,
    int loteId,
  ) async {
    if (!AppModule.lotes.canOpen(user)) {
      throw const ApiException(
        'No tienes permiso para consultar las presentaciones de este lote.',
        statusCode: 403,
      );
    }
    if (loteId <= 0) {
      throw const ApiException('El lote solicitado no es válido.');
    }
    final response = await _api.request(
      'GET',
      'lotes/$loteId/presentaciones-cosecha',
    );
    return CosechaConfiguracion.fromJson(response);
  }

  Future<ModuleRecord> createCosecha(
    AuthUser user, {
    required int loteId,
    required String cantidad,
    required int unidadMedidaId,
    int? catalogoTamanoConteoId,
    String? fechaCosecha,
    String? observaciones,
  }) async {
    if (!CosechaPermissions.canCreate(user)) {
      throw const ApiException(
        'No tienes permiso para registrar cosechas.',
        statusCode: 403,
      );
    }
    final cleanCantidad = cantidad.trim().replaceAll(',', '.');
    final cleanFecha = fechaCosecha?.trim();
    final cleanObs = observaciones?.trim();
    final body = <String, Object?>{
      'loteid': loteId,
      'cantidad': cleanCantidad,
      'unidadmedidaid': unidadMedidaId,
      'catalogotamanoconteoid': ?catalogoTamanoConteoId,
      if (cleanFecha != null && cleanFecha.isNotEmpty)
        'fechacosecha': cleanFecha,
      if (cleanObs != null && cleanObs.isNotEmpty) 'observaciones': cleanObs,
    };
    final response = await _api.request(
      'POST',
      AppModule.producciones.endpoint,
      body: body,
    );
    return ModuleRecord.fromJson(
      response,
      idField: AppModule.producciones.idField,
      titleField: AppModule.producciones.titleField,
      fallbackTitle: 'Cosecha',
      fields: AppModule.producciones.fields,
    );
  }

  Future<TareasPlantaPage> loadTareasPlanta(
    AuthUser user, {
    String? estado,
    int page = 1,
  }) async {
    if (!PlantaPermissions.canViewTareas(user)) {
      throw const ApiException(
        'No tienes permiso para consultar las tareas de planta.',
        statusCode: 403,
      );
    }
    if (page < 1) {
      throw const ApiException('La página solicitada no es válida.');
    }
    final params = <String, String>{
      'page': '$page',
      if (estado != null && estado.isNotEmpty) 'estado': estado,
    };
    final response = await _api.request(
      'GET',
      AppModule.tareasPlanta.endpoint,
      queryParameters: params,
    );
    return TareasPlantaPage.fromJson(response);
  }

  Future<TareaPlantaDetail> loadTareaPlantaDetail(
    AuthUser user,
    int asignacionId,
  ) async {
    if (!PlantaPermissions.canViewTareas(user)) {
      throw const ApiException(
        'No tienes permiso para consultar esta tarea de planta.',
        statusCode: 403,
      );
    }
    if (asignacionId <= 0) {
      throw const ApiException('La tarea solicitada no es válida.');
    }
    final response = await _api.request(
      'GET',
      '${AppModule.tareasPlanta.endpoint}/$asignacionId',
    );
    return TareaPlantaDetail.fromJson(response);
  }

  Future<TareaPlantaDetail> completeTareaPlanta(
    AuthUser user, {
    required int loteProduccionId,
    required int asignacionId,
    required List<Map<String, Object?>> parametros,
  }) async {
    if (!PlantaPermissions.canViewTareas(user)) {
      throw const ApiException(
        'No tienes permiso para completar esta tarea de planta.',
        statusCode: 403,
      );
    }
    if (loteProduccionId <= 0 || asignacionId <= 0) {
      throw const ApiException('La tarea solicitada no es válida.');
    }
    final response = await _api.request(
      'POST',
      'planta/lotes-produccion/$loteProduccionId/tareas/$asignacionId/completar',
      body: {'parametros': parametros},
    );
    return TareaPlantaDetail.fromJson(response);
  }

  Future<RecepcionesPlantaPage> loadRecepcionesPlanta(
    AuthUser user, {
    bool recibido = false,
    int page = 1,
  }) async {
    if (!PlantaPermissions.canViewRecepciones(user)) {
      throw const ApiException(
        'No tienes permiso para consultar las recepciones de planta.',
        statusCode: 403,
      );
    }
    if (page < 1) {
      throw const ApiException('La página solicitada no es válida.');
    }
    final response = await _api.request(
      'GET',
      AppModule.recepcionesPlanta.endpoint,
      queryParameters: {'recibido': recibido ? '1' : '0', 'page': '$page'},
    );
    return RecepcionesPlantaPage.fromJson(response);
  }

  Future<RecepcionPlantaRecord> loadRecepcionPlantaDetail(
    AuthUser user,
    int pedidoId,
  ) async {
    if (!PlantaPermissions.canViewRecepciones(user)) {
      throw const ApiException(
        'No tienes permiso para consultar esta recepción.',
        statusCode: 403,
      );
    }
    if (pedidoId <= 0) {
      throw const ApiException('La recepción solicitada no es válida.');
    }
    final response = await _api.request(
      'GET',
      '${AppModule.recepcionesPlanta.endpoint}/$pedidoId',
    );
    return RecepcionPlantaRecord.fromJson(response);
  }

  Future<RecepcionPlantaRecord> confirmRecepcionPlanta(
    AuthUser user, {
    required int pedidoId,
    required Map<String, String> cantidades,
  }) async {
    if (!PlantaPermissions.canConfirmRecepcion(user)) {
      throw const ApiException(
        'No tienes permiso para confirmar recepciones en planta.',
        statusCode: 403,
      );
    }
    if (pedidoId <= 0) {
      throw const ApiException('La recepción solicitada no es válida.');
    }
    final response = await _api.request(
      'POST',
      '${AppModule.recepcionesPlanta.endpoint}/$pedidoId/confirmar',
      body: {'cantidades': cantidades},
    );
    return RecepcionPlantaRecord.fromJson(response);
  }

  Future<ProcesamientoRecorrido> loadProcesamientoRecorrido(
    AuthUser user,
    int loteProduccionId,
  ) async {
    if (!PlantaPermissions.canViewProcesamiento(user)) {
      throw const ApiException(
        'No tienes permiso para consultar el procesamiento de planta.',
        statusCode: 403,
      );
    }
    final response = await _api.request(
      'GET',
      'planta/lotes-produccion/$loteProduccionId',
    );
    return ProcesamientoRecorrido.fromJson(response);
  }

  Future<PedidosPage> loadPedidosMovil(
    AuthUser user, {
    required PedidoTipo tipo,
    String? estado,
    int page = 1,
  }) async {
    final allowed = tipo == PedidoTipo.agricola
        ? PedidoPermissions.canViewAgricola(user)
        : PedidoPermissions.canViewDistribucion(user);
    if (!allowed) {
      throw const ApiException(
        'No tienes permiso para consultar este tipo de pedidos.',
        statusCode: 403,
      );
    }
    final query = <String, String>{
      'page': '$page',
      if (estado != null && estado.trim().isNotEmpty) 'estado': estado.trim(),
    };
    final response = await _api.request(
      'GET',
      tipo.endpoint,
      queryParameters: query,
    );
    return PedidosPage.fromJson(response);
  }

  Future<PedidoRecord> loadPedidoMovilDetail(
    AuthUser user, {
    required PedidoTipo tipo,
    required int id,
  }) async {
    final allowed = tipo == PedidoTipo.agricola
        ? PedidoPermissions.canViewAgricola(user)
        : PedidoPermissions.canViewDistribucion(user);
    if (!allowed) {
      throw const ApiException(
        'No tienes permiso para consultar el detalle de este pedido.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', '${tipo.endpoint}/$id');
    return PedidoRecord.fromJson(response);
  }

  Future<PedidoRecord> createPedidoMovil(
    AuthUser user, {
    required PedidoTipo tipo,
    required Map<String, dynamic> body,
  }) async {
    final allowed = tipo == PedidoTipo.agricola
        ? PedidoPermissions.canCreateAgricola(user)
        : PedidoPermissions.canCreateDistribucion(user);
    if (!allowed) {
      throw const ApiException(
        'No tienes permiso para crear este tipo de pedido.',
        statusCode: 403,
      );
    }
    final response = await _api.request('POST', tipo.endpoint, body: body);
    return PedidoRecord.fromJson(response);
  }

  Future<QrResolucionResult> resolveEnvioQr(
    AuthUser user,
    String codigo,
  ) async {
    if (!QrPermissions.canUseQr(user)) {
      throw const ApiException(
        'No tienes permiso para consultar o validar códigos QR de envío.',
        statusCode: 403,
      );
    }
    final normalized = codigo.trim();
    final response = await _api.request(
      'POST',
      'envios/qr/resolver',
      body: {'codigo': normalized},
    );
    return QrResolucionResult.fromJson(response, codigo: normalized);
  }

  Future<EnvioResumen> loadEnvioMovilDetail(
    AuthUser user, {
    required EnvioTipo tipo,
    required int id,
  }) async {
    if (!QrPermissions.canUseQr(user)) {
      throw const ApiException(
        'No tienes permiso para consultar este envío.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', 'envios/${tipo.value}/$id');
    final root =
        response is Map<String, dynamic> &&
            response['data'] is Map<String, dynamic>
        ? response['data'] as Map<String, dynamic>
        : response is Map<String, dynamic>
        ? response
        : const <String, dynamic>{};
    return EnvioResumen.fromJson(root);
  }

  Future<RutasEntregaPage> loadRutasEntrega(
    AuthUser user, {
    int page = 1,
  }) async {
    if (!EntregaPermissions.canViewRutas(user)) {
      throw const ApiException(
        'No tienes permiso para consultar las rutas de entrega.',
        statusCode: 403,
      );
    }
    final response = await _api.request(
      'GET',
      'rutas-multi',
      queryParameters: {'page': '$page'},
    );
    return RutasEntregaPage.fromJson(response);
  }

  Future<RutaEntregaRecord> loadRutaEntregaDetail(
    AuthUser user,
    int rutaId,
  ) async {
    if (!EntregaPermissions.canViewRutas(user)) {
      throw const ApiException(
        'No tienes permiso para consultar esta ruta de entrega.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', 'rutas-multi/$rutaId');
    return RutaEntregaRecord.fromJson(response);
  }

  Future<RutaEntregaRecord> updateRutaEntregaEstado(
    AuthUser user, {
    required int rutaId,
    required String estado,
  }) async {
    if (!EntregaPermissions.canUpdateAvance(user)) {
      throw const ApiException(
        'No tienes permiso para registrar avances en esta entrega.',
        statusCode: 403,
      );
    }
    final response = await _api.request(
      'PATCH',
      'rutas-multi/$rutaId',
      body: {'estado': estado},
    );
    return RutaEntregaRecord.fromJson(response);
  }

  Future<List<EnvioResumen>> loadEnviosMovilList(
    AuthUser user, {
    required EnvioTipo tipo,
    String? estado,
    int page = 1,
  }) async {
    final allowed = tipo == EnvioTipo.agricola
        ? EntregaPermissions.canViewEnviosAgricolas(user)
        : EntregaPermissions.canViewEnviosDistribucion(user);
    if (!allowed) {
      throw const ApiException(
        'No tienes permiso para consultar este tipo de envíos.',
        statusCode: 403,
      );
    }
    final query = <String, String>{
      'page': '$page',
      if (estado != null && estado.trim().isNotEmpty) 'estado': estado.trim(),
    };
    final response = await _api.request(
      'GET',
      'envios/${tipo.value}',
      queryParameters: query,
    );
    final rows = response is List
        ? response
        : response is Map<String, dynamic> && response['data'] is List
        ? response['data'] as List
        : const [];
    final items = <EnvioResumen>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        final item = EnvioResumen.fromJson(row);
        if (item.id > 0) items.add(item);
      }
    }
    return items;
  }

  Future<List<AlmacenFiltroOption>> loadAuthorizedAlmacenes(
    AuthUser user,
  ) async {
    if (!InventarioPermissions.canViewExistencias(user)) {
      throw const ApiException(
        'No tienes permiso para consultar los almacenes autorizados.',
        statusCode: 403,
      );
    }
    final response = await _api.request('GET', AppModule.almacenes.endpoint);
    return AlmacenFiltroOption.listFromJson(response);
  }

  Future<AlmacenExistenciasPage> loadAlmacenExistencias(
    AuthUser user,
    int almacenId, {
    String? query,
    String? estado,
    int page = 1,
  }) async {
    if (!InventarioPermissions.canViewExistencias(user)) {
      throw const ApiException(
        'No tienes permiso para consultar las existencias de este almacén.',
        statusCode: 403,
      );
    }
    if (almacenId <= 0 || page < 1) {
      throw const ApiException('El almacén solicitado no es válido.');
    }
    final params = <String, String>{
      'page': '$page',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (estado != null && estado.trim().isNotEmpty) 'estado': estado.trim(),
    };
    final response = await _api.request(
      'GET',
      'almacenes/$almacenId/existencias',
      queryParameters: params,
    );
    return AlmacenExistenciasPage.fromJson(response);
  }

  Future<InventarioMovimientosPage> loadAlmacenMovimientos(
    AuthUser user,
    int almacenId, {
    String? naturaleza,
    int? insumoId,
    int page = 1,
  }) async {
    if (!InventarioPermissions.canViewMovimientos(user)) {
      throw const ApiException(
        'No tienes permiso para consultar el historial de movimientos.',
        statusCode: 403,
      );
    }
    if (almacenId <= 0 || page < 1) {
      throw const ApiException('El almacén solicitado no es válido.');
    }
    final params = <String, String>{
      'page': '$page',
      if (naturaleza != null && naturaleza.isNotEmpty) 'naturaleza': naturaleza,
      if (insumoId != null && insumoId > 0) 'insumoid': '$insumoId',
    };
    final response = await _api.request(
      'GET',
      'almacenes/$almacenId/movimientos',
      queryParameters: params,
    );
    return InventarioMovimientosPage.fromJson(response);
  }

  Future<InventarioMovimientoRecord> registerAlmacenMovimiento(
    AuthUser user, {
    required String naturaleza,
    required int almacenId,
    required int insumoId,
    required int tipoMovimientoId,
    required String fecha,
    required String cantidad,
    String? destinoMotivo,
    String? referencia,
    String? observaciones,
    String? partida,
  }) async {
    final allowed = naturaleza == 'ingreso'
        ? InventarioPermissions.canRegisterIngreso(user)
        : InventarioPermissions.canRegisterSalida(user);
    if (!allowed) {
      throw const ApiException(
        'No tienes permiso para registrar este movimiento de inventario.',
        statusCode: 403,
      );
    }
    if (naturaleza != 'ingreso' && naturaleza != 'salida') {
      throw const ApiException('La naturaleza del movimiento no es válida.');
    }
    final cleanCantidad = cantidad.trim().replaceAll(',', '.');
    final cleanMotivo = destinoMotivo?.trim();
    final cleanRef = referencia?.trim();
    final cleanObs = observaciones?.trim();
    final cleanPartida = partida?.trim();
    final body = <String, Object?>{
      'almacenid': almacenId,
      'insumoid': insumoId,
      'tipo_movimiento_almacenid': tipoMovimientoId,
      'fecha': fecha.trim(),
      'cantidad': cleanCantidad,
      if (cleanMotivo != null && cleanMotivo.isNotEmpty)
        'destino_motivo': cleanMotivo,
      if (cleanRef != null && cleanRef.isNotEmpty) 'referencia': cleanRef,
      if (cleanObs != null && cleanObs.isNotEmpty) 'observaciones': cleanObs,
      if (cleanPartida != null && cleanPartida.isNotEmpty)
        'partida': cleanPartida,
    };
    final response = await _api.request(
      'POST',
      'almacen-movimientos/$naturaleza',
      body: body,
    );
    return InventarioMovimientoRecord.fromJson(response);
  }
}
