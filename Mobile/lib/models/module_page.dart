import 'api_exception.dart';

class ModulePage {
  const ModulePage(this.records, {this.currentPage = 1, this.lastPage = 1});

  factory ModulePage.fromJson(
    Object? json, {
    required String idField,
    required String? titleField,
    required String fallbackTitle,
    required Map<String, String> fields,
  }) {
    Object? rows = json;
    var current = 1;
    var last = 1;
    if (json is Map<String, dynamic>) {
      if (json case {
        'data': List data,
        'current_page': int page,
        'last_page': int end,
      } when page >= 1 && end >= page) {
        rows = data;
        current = page;
        last = end;
      } else {
        throw _invalid;
      }
    }
    if (rows is! List) throw _invalid;
    final records = <ModuleRecord>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic> ||
          row[idField] is! int ||
          row[idField] <= 0) {
        throw _invalid;
      }
      String? text(String key) {
        final value = row[key];
        if (value == null) return null;
        if (value is! String && value is! num && value is! bool) throw _invalid;
        final result = value.toString().trim();
        return result.isEmpty ? null : result;
      }

      records.add(
        ModuleRecord(
          title:
              (titleField == null ? null : text(titleField)) ??
              '$fallbackTitle #${row[idField]}',
          details: Map.unmodifiable({
            'Identificador': row[idField].toString(),
            for (final field in fields.entries)
              field.value: text(field.key) ?? 'Sin registrar',
          }),
        ),
      );
    }
    return ModulePage(
      List.unmodifiable(records),
      currentPage: current,
      lastPage: last,
    );
  }

  static const _invalid = ApiException(
    'La API devolvió una lista de registros inválida.',
  );

  final List<ModuleRecord> records;
  final int currentPage;
  final int lastPage;
}

class ModuleRecord {
  const ModuleRecord({required this.title, required this.details});

  final String title;
  final Map<String, String> details;
}
