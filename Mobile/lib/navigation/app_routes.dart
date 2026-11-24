import '../models/pedido_models.dart';
import '../models/qr_envio_models.dart';
import 'app_module.dart';

/// Rutas de la app. Los destinos con parámetros se construyen aquí, con tipos,
/// para que ninguna pantalla arme texto de rutas a mano.
abstract final class AppRoutes {
  static const home = '/';
  static const register = '/register';
  static const trazabilidadPublica = '/trazabilidad';
  static const profile = '/profile';
  static const qr = '/modules/qr';
  static const entregas = '/modules/entregas';
  static const incidenteNuevo = '/modules/incidentes/nuevo';
  static const pedidosGestion = '/modules/pedidos/gestion';
  static const pedidoNuevo = '/modules/pedidos/nuevo';
  static const inventarioAlertas = '/modules/almacenes/alertas';

  static String nuevo(AppModule module) => '${module.route}/nuevo';
  static String nueva(AppModule module) => '${module.route}/nueva';
  static String detalle(AppModule module, int id) => '${module.route}/$id';
  static String loteEditar(int id) => '${AppModule.lotes.route}/$id/editar';
  static String loteHistorial(int id) =>
      '${AppModule.lotes.route}/$id/historial';
  static String actividadCerrar(int id) =>
      '${AppModule.actividades.route}/$id/cerrar';
  static String entregaRuta(int id) => '$entregas/ruta/$id';
  static String envio(EnvioTipo tipo, int id) =>
      '/modules/envios/${tipo.value}/$id';
  static String pedido(PedidoTipo tipo, int id) =>
      '${AppModule.pedidos.route}/${tipo.value}/$id';
  static String loteProduccion(int id) =>
      '/modules/planta/lotes-produccion/$id';
}
