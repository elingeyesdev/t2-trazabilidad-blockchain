import '../models/api_exception.dart';
import '../models/auth_user.dart';
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
      queryParameters: {'page': '$page'},
    );
    final result = ModulePage.fromJson(
      response,
      idField: AppModule.actividades.idField,
      titleField: AppModule.actividades.titleField,
      fallbackTitle: 'Actividad',
      fields: AppModule.actividades.fields,
    );
    final rows = response is Map<String, dynamic> ? response['data'] : response;
    if (rows is! List ||
        rows.any(
          (row) => row is! Map<String, dynamic> || row['loteid'] != loteId,
        ) ||
        result.currentPage != page) {
      throw const ApiException(
        'La información recibida no corresponde al historial solicitado.',
      );
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
}
