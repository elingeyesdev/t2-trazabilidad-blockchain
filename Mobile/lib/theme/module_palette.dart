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

// Todos los módulos comparten el verde de la marca: el color se reserva para
// el estado de cada registro (pendiente, completado, cancelado...).
const _tone = Color(0xFFDCEBD3);
const _ink = Color(0xFF23552F);

extension ModulePalette on AppModule {
  ModuleLook get look => switch (this) {
    AppModule.lotes => const ModuleLook(_tone, _ink, 'Cultivos y ubicación'),
    AppModule.actividades => const ModuleLook(_tone, _ink, 'Tareas y fechas'),
    AppModule.producciones => const ModuleLook(
      _tone,
      _ink,
      'Cantidades y fechas',
    ),
    AppModule.tareasPlanta => const ModuleLook(
      _tone,
      _ink,
      'Etapas y máquinas',
    ),
    AppModule.recepcionesPlanta => const ModuleLook(
      _tone,
      _ink,
      'Pesaje y recepción',
    ),
    AppModule.almacenes => const ModuleLook(
      _tone,
      _ink,
      'Lugares de almacenamiento',
    ),
    AppModule.insumos => const ModuleLook(
      _tone,
      _ink,
      'Materiales y existencias',
    ),
    AppModule.movimientos => const ModuleLook(
      _tone,
      _ink,
      'Entradas y salidas',
    ),
    AppModule.certificaciones => const ModuleLook(
      _tone,
      _ink,
      'Certificados de lotes',
    ),
    AppModule.pedidos => const ModuleLook(_tone, _ink, 'Solicitudes y estado'),
    AppModule.incidentes => const ModuleLook(
      _tone,
      _ink,
      'Problemas reportados',
    ),
    AppModule.rutas => const ModuleLook(_tone, _ink, 'Recorridos y salidas'),
    AppModule.asignaciones => const ModuleLook(
      _tone,
      _ink,
      'Envíos y transporte',
    ),
    AppModule.documentos => const ModuleLook(_tone, _ink, 'Papeles de entrega'),
    AppModule.usuarios => const ModuleLook(_tone, _ink, 'Cuentas del equipo'),
  };
}
