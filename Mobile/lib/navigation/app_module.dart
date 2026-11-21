import 'package:flutter/material.dart';

import '../models/auth_user.dart';

enum AppModule {
  lotes(
    'Lotes',
    'lotes',
    'lotes.view',
    Icons.landscape_rounded,
    'loteid',
    'nombre',
    {'ubicacion': 'Ubicación', 'superficie': 'Superficie'},
  ),
  actividades(
    'Actividades',
    'actividades',
    'lotes.view',
    Icons.agriculture_rounded,
    'actividadid',
    'descripcion',
    {'fecha_planificada': 'Fecha planificada', 'fechainicio': 'Inicio'},
  ),
  producciones(
    'Cosechas',
    'producciones',
    'lotes.view',
    Icons.grass_rounded,
    'produccionid',
    null,
    {'cantidad': 'Cantidad', 'fechacosecha': 'Fecha de cosecha'},
  ),
  tareasPlanta(
    'Tareas de planta',
    'planta/tareas',
    'lote_produccion.view',
    Icons.precision_manufacturing_rounded,
    'asignacionetapaplantaid',
    null,
    {'estado': 'Estado', 'orden': 'Etapa'},
  ),
  almacenes(
    'Almacenes',
    'almacenes',
    'inventario.view',
    Icons.warehouse_rounded,
    'almacenid',
    'nombre',
    {'ubicacion': 'Ubicación', 'capacidad': 'Capacidad'},
  ),
  insumos(
    'Insumos',
    'insumos',
    'inventario.view',
    Icons.inventory_2_rounded,
    'insumoid',
    'nombre',
    {'stock': 'Stock', 'descripcion': 'Descripción'},
  ),
  movimientos(
    'Movimientos de almacén',
    'almacen-movimientos',
    'almacen.movimientos.view',
    Icons.swap_horiz_rounded,
    'almacen_movimientoid',
    'referencia',
    {'fecha': 'Fecha', 'cantidad': 'Cantidad'},
  ),
  certificaciones(
    'Certificaciones',
    'certificaciones',
    'certificaciones.view',
    Icons.verified_rounded,
    'certificacionid',
    'codigo_certificado',
    {'resultado': 'Resultado', 'fecha_certificacion': 'Fecha de certificación'},
  ),
  pedidos(
    'Pedidos',
    'pedidos',
    'pedidos.view',
    Icons.receipt_long_rounded,
    'pedidoid',
    'numero_solicitud',
    {'nombre_planta': 'Planta', 'estado': 'Estado'},
  ),
  incidentes(
    'Incidentes',
    'incidentes',
    'incidentes.view',
    Icons.report_problem_rounded,
    'incidenteenvioid',
    'tipo',
    {'descripcion': 'Descripción', 'estado': 'Estado'},
  ),
  rutas(
    'Rutas',
    'rutas-multi',
    'rutas_multi.view',
    Icons.route_rounded,
    'rutamultientregaid',
    'nombre',
    {'estado': 'Estado', 'fecha_salida': 'Salida'},
  ),
  asignaciones(
    'Asignaciones',
    'asignaciones-multiples',
    'asignaciones.view',
    Icons.local_shipping_rounded,
    'envioasignacionmultipleid',
    'vehiculo_ref',
    {'estado': 'Estado', 'fecha_asignacion': 'Fecha de asignación'},
  ),
  documentos(
    'Documentos de entrega',
    'documentos-entrega',
    'documentos.view',
    Icons.description_rounded,
    'documentoentregaid',
    'titulo',
    {'tipo_documento': 'Tipo'},
  ),
  usuarios(
    'Usuarios',
    'usuarios',
    'usuarios.admin',
    Icons.groups_rounded,
    'usuarioid',
    'nombre',
    {
      'apellido': 'Apellido',
      'email': 'Correo',
      'estado_cuenta': 'Estado de cuenta',
    },
  );

  const AppModule(
    this.label,
    this.endpoint,
    this.permission,
    this.icon,
    this.idField,
    this.titleField,
    this.fields,
  );

  final String label;
  final String endpoint;
  final String permission;
  final IconData icon;
  final String idField;
  final String? titleField;
  final Map<String, String> fields;

  String get route => '/modules/$endpoint';

  String get description => switch (this) {
    AppModule.lotes => 'Consulta tus lotes y su ubicación.',
    AppModule.actividades => 'Revisa las tareas de campo y sus fechas.',
    AppModule.producciones => 'Consulta las cantidades y fechas de cosecha.',
    AppModule.tareasPlanta =>
      'Revisa y completa tus etapas asignadas en planta.',
    AppModule.almacenes => 'Encuentra los almacenes y su información.',
    AppModule.insumos => 'Consulta semillas, materiales y existencias.',
    AppModule.movimientos => 'Revisa las entradas y salidas del almacén.',
    AppModule.certificaciones => 'Consulta los certificados de los lotes.',
    AppModule.pedidos => 'Revisa los pedidos y su estado.',
    AppModule.incidentes => 'Consulta los problemas reportados en entregas.',
    AppModule.rutas => 'Consulta los recorridos y sus fechas.',
    AppModule.asignaciones => 'Revisa los envíos y transportes asignados.',
    AppModule.documentos => 'Encuentra los documentos de las entregas.',
    AppModule.usuarios => 'Consulta las cuentas de los usuarios.',
  };

  bool canOpen(AuthUser user) {
    if (!user.permissions.contains(permission)) return false;
    if (this == AppModule.tareasPlanta) {
      return !user.roles.contains('jefe_planta');
    }
    if (this != AppModule.asignaciones ||
        user.roles.any(const {'admin', 'transportista'}.contains)) {
      return true;
    }
    // Esta consulta corresponde al trayecto agrícola, no a la distribución comercial.
    return !user.roles.any(
      const {'mayorista', 'jefe_mayorista', 'minorista'}.contains,
    );
  }
}
