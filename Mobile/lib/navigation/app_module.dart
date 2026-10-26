import 'package:flutter/material.dart';

import '../models/auth_user.dart';

enum AppModule {
  lotes(
    'Lotes',
    'lotes',
    'lotes.view',
    Icons.landscape_outlined,
    'loteid',
    'nombre',
    {'ubicacion': 'Ubicación', 'superficie': 'Superficie'},
  ),
  actividades(
    'Actividades',
    'actividades',
    'lotes.view',
    Icons.event_outlined,
    'actividadid',
    'descripcion',
    {'fecha_planificada': 'Fecha planificada', 'fechainicio': 'Inicio'},
  ),
  producciones(
    'Cosechas',
    'producciones',
    'lotes.view',
    Icons.eco_outlined,
    'produccionid',
    null,
    {'cantidad': 'Cantidad', 'fechacosecha': 'Fecha de cosecha'},
  ),
  almacenes(
    'Almacenes',
    'almacenes',
    'inventario.view',
    Icons.warehouse_outlined,
    'almacenid',
    'nombre',
    {'ubicacion': 'Ubicación', 'capacidad': 'Capacidad'},
  ),
  insumos(
    'Insumos',
    'insumos',
    'inventario.view',
    Icons.science_outlined,
    'insumoid',
    'nombre',
    {'stock': 'Stock', 'descripcion': 'Descripción'},
  ),
  movimientos(
    'Movimientos de almacén',
    'almacen-movimientos',
    'almacen.movimientos.view',
    Icons.swap_horiz,
    'almacen_movimientoid',
    'referencia',
    {'fecha': 'Fecha', 'cantidad': 'Cantidad'},
  ),
  certificaciones(
    'Certificaciones',
    'certificaciones',
    'certificaciones.view',
    Icons.verified_outlined,
    'certificacionid',
    'codigo_certificado',
    {'resultado': 'Resultado', 'fecha_certificacion': 'Fecha de certificación'},
  ),
  pedidos(
    'Pedidos',
    'pedidos',
    'pedidos.view',
    Icons.shopping_cart_outlined,
    'pedidoid',
    'numero_solicitud',
    {'nombre_planta': 'Planta', 'estado': 'Estado'},
  ),
  incidentes(
    'Incidentes',
    'incidentes',
    'incidentes.view',
    Icons.warning_amber_outlined,
    'incidenteenvioid',
    'tipo',
    {'descripcion': 'Descripción', 'estado': 'Estado'},
  ),
  rutas(
    'Rutas',
    'rutas-multi',
    'rutas_multi.view',
    Icons.route_outlined,
    'rutamultientregaid',
    'nombre',
    {'estado': 'Estado', 'fecha_salida': 'Salida'},
  ),
  asignaciones(
    'Asignaciones',
    'asignaciones-multiples',
    'asignaciones.view',
    Icons.local_shipping_outlined,
    'envioasignacionmultipleid',
    'vehiculo_ref',
    {'estado': 'Estado', 'fecha_asignacion': 'Fecha de asignación'},
  ),
  documentos(
    'Documentos de entrega',
    'documentos-entrega',
    'documentos.view',
    Icons.description_outlined,
    'documentoentregaid',
    'titulo',
    {'tipo_documento': 'Tipo'},
  ),
  usuarios(
    'Usuarios',
    'usuarios',
    'usuarios.admin',
    Icons.people_outline,
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

  bool canOpen(AuthUser user) => user.permissions.contains(permission);
}
