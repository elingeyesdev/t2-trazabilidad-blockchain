import '../models/api_exception.dart';
import '../models/auth_user.dart';
import '../models/module_page.dart';
import '../navigation/app_module.dart';
import 'api_client.dart';

class ModuleService {
  const ModuleService(this._api);

  final ApiClient _api;

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
