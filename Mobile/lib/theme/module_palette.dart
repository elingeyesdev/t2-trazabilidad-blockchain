import 'package:flutter/material.dart';

import '../navigation/app_module.dart';

/// Color propio de cada módulo para reconocerlo de un vistazo, aun sin leer.
/// [tone] es el fondo suave y [ink] el color del ícono y los textos sobre él.
class ModuleLook {
  const ModuleLook(this.tone, this.ink, this.hint);
  final Color tone;
  final Color ink;

  /// Texto corto para mosaicos: dice qué se encuentra dentro.
  final String hint;
}

extension ModulePalette on AppModule {
  ModuleLook get look => switch (this) {
    AppModule.lotes => const ModuleLook(
      Color(0xFFDCEBD3),
      Color(0xFF23552F),
      'Cultivos y ubicación',
    ),
    AppModule.actividades => const ModuleLook(
      Color(0xFFFBE8B8),
      Color(0xFF654600),
      'Tareas y fechas',
    ),
    AppModule.producciones => const ModuleLook(
      Color(0xFFF7DCC6),
      Color(0xFF853914),
      'Cantidades y fechas',
    ),
    AppModule.tareasPlanta => const ModuleLook(
      Color(0xFFDCEBD3),
      Color(0xFF23552F),
      'Etapas y máquinas',
    ),
    AppModule.recepcionesPlanta => const ModuleLook(
      Color(0xFFDCEBD3),
      Color(0xFF23552F),
      'Pesaje y recepción',
    ),
    AppModule.almacenes => const ModuleLook(
      Color(0xFFE9DDCC),
      Color(0xFF5A452D),
      'Lugares de almacenamiento',
    ),
    AppModule.insumos => const ModuleLook(
      Color(0xFFD2E9E3),
      Color(0xFF1B5A50),
      'Materiales y existencias',
    ),
    AppModule.movimientos => const ModuleLook(
      Color(0xFFD7E6F0),
      Color(0xFF214F6E),
      'Entradas y salidas',
    ),
    AppModule.certificaciones => const ModuleLook(
      Color(0xFFE6DDF1),
      Color(0xFF4D3677),
      'Certificados de lotes',
    ),
    AppModule.pedidos => const ModuleLook(
      Color(0xFFF4DADA),
      Color(0xFF822F2E),
      'Solicitudes y estado',
    ),
    AppModule.incidentes => const ModuleLook(
      Color(0xFFF8D8CC),
      Color(0xFF962E12),
      'Problemas reportados',
    ),
    AppModule.rutas => const ModuleLook(
      Color(0xFFE0E7D2),
      Color(0xFF42552A),
      'Recorridos y salidas',
    ),
    AppModule.asignaciones => const ModuleLook(
      Color(0xFFDFE2F3),
      Color(0xFF333E7A),
      'Envíos y transporte',
    ),
    AppModule.documentos => const ModuleLook(
      Color(0xFFECE6D7),
      Color(0xFF4A4535),
      'Papeles de entrega',
    ),
    AppModule.usuarios => const ModuleLook(
      Color(0xFFE4E0EA),
      Color(0xFF3D3949),
      'Cuentas del equipo',
    ),
  };
}
