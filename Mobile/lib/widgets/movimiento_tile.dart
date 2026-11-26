import 'package:flutter/material.dart';

import '../models/inventario_models.dart';
import '../theme/app_glyphs.dart';
import '../theme/app_theme.dart';

/// Un movimiento de inventario, en palabras: qué producto, si entró o salió,
/// cuánto, cuánto quedó y quién lo hizo. La dirección se ve con ícono, color
/// y palabra, nunca solo con color.
class MovimientoTile extends StatelessWidget {
  const MovimientoTile({super.key, required this.movimiento, this.showAlmacen});

  final InventarioMovimientoRecord movimiento;

  /// Muestra el nombre del almacén (útil cuando la lista mezcla varios).
  final bool? showAlmacen;

  static ({String label, IconData icon, Color tone, Color ink}) lookOf(
    InventarioMovimientoRecord m,
  ) {
    if (m.isIngreso) {
      return (
        label: 'Entrada',
        icon: AppIcons.arrowDownLeft,
        tone: AppTheme.sprout,
        ink: AppTheme.fieldDeep,
      );
    }
    if (m.isSalida) {
      return (
        label: 'Salida',
        icon: AppIcons.arrowUpRight,
        tone: AppTheme.claySoft,
        ink: AppTheme.clay,
      );
    }
    return (
      label: 'Ajuste',
      icon: AppIcons.sliders,
      tone: AppTheme.skySoft,
      ink: AppTheme.sky,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final look = lookOf(m);
    final theme = Theme.of(context).textTheme;
    final details = <String>[
      if (showAlmacen == true && m.almacenNombre != null)
        'Almacén: ${m.almacenNombre}',
      if (m.destinoMotivo != null) 'Motivo: ${m.destinoMotivo}',
      if (m.referencia != null) 'Referencia: ${m.referencia}',
      if (m.usuarioNombre != null) 'Responsable: ${m.usuarioNombre}',
    ];
    return Container(
      key: ValueKey('movimiento.${m.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: look.tone,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(look.icon, size: 22, color: look.ink),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.insumoNombre, style: theme.titleMedium),
                Text(
                  '${look.label} · ${m.tipoNombre}',
                  style: theme.bodyMedium?.copyWith(
                    color: look.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (m.saldoAnterior != null && m.saldoPosterior != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Quedan ${formatInventarioDecimal(m.saldoPosterior!)}${m.unidad != null ? ' ${m.unidad}' : ''} (antes ${formatInventarioDecimal(m.saldoAnterior!)})',
                    style: theme.bodyMedium,
                  ),
                ],
                for (final line in details) ...[
                  const SizedBox(height: 2),
                  Text(line, style: theme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            m.formattedQuantity,
            style: AppTheme.display(
              20,
              1.2,
              800,
              -.3,
            ).copyWith(color: look.ink),
          ),
        ],
      ),
    );
  }
}

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "2026-11-23..." -> "Hoy", "Ayer" o "23 de noviembre". Si no se puede leer
/// la fecha, devuelve el texto tal cual.
String describeDay(String raw, {DateTime? now}) {
  final date = DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
  if (date == null) return raw;
  final today = now ?? DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(date.year, date.month, date.day)).inDays;
  if (days == 0) return 'Hoy';
  if (days == 1) return 'Ayer';
  final year = date.year == today.year ? '' : ' de ${date.year}';
  return '${date.day} de ${_months[date.month - 1]}$year';
}

/// Lista de movimientos agrupada por día, con el día como encabezado.
List<Widget> movimientoGroups(
  BuildContext context,
  List<InventarioMovimientoRecord> items, {
  bool showAlmacen = false,
}) {
  final widgets = <Widget>[];
  String? current;
  for (final m in items) {
    final day = describeDay(m.fecha);
    if (day != current) {
      current = day;
      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 12, bottom: 8),
          child: Semantics(
            header: true,
            child: Text(day, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
      );
    }
    widgets.add(MovimientoTile(movimiento: m, showAlmacen: showAlmacen));
    widgets.add(const SizedBox(height: 10));
  }
  return widgets;
}
