import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/pedido_models.dart';
import '../../navigation/app_module.dart';
import '../../navigation/app_routes.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/form_validation.dart';
import 'module_access_denied.dart';

class PedidoFormScreen extends StatefulWidget {
  const PedidoFormScreen({
    super.key,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.onPedidoCreated,
  });

  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final VoidCallback? onPedidoCreated;

  @override
  State<PedidoFormScreen> createState() => _PedidoFormScreenState();
}

class _DistDraftLineControllers {
  _DistDraftLineControllers()
    : producto = TextEditingController(),
      presentacion = TextEditingController(),
      cantidad = TextEditingController(),
      partida = TextEditingController();

  final TextEditingController producto;
  final TextEditingController presentacion;
  final TextEditingController cantidad;
  final TextEditingController partida;

  int? selectedProductoId;
  int? selectedPresentacionId;

  void dispose() {
    producto.dispose();
    presentacion.dispose();
    cantidad.dispose();
    partida.dispose();
  }
}

enum _FormaPedidoAgricola {
  kg('kg', 'Kilogramos'),
  empaques('empaques', 'Empaques'),
  unidades('unidades', 'Unidades');

  const _FormaPedidoAgricola(this.value, this.label);
  final String value;
  final String label;
}

class _AgricolaLineDraft {
  _AgricolaLineDraft({this.almacenId})
    : cantidadCtrl = TextEditingController(),
      notaCtrl = TextEditingController();

  int? almacenId;
  String? productoRef;
  int? partidaId;
  _FormaPedidoAgricola forma = _FormaPedidoAgricola.kg;
  int? tipoEmpaqueId;
  int? calibreId;
  final TextEditingController cantidadCtrl;
  final TextEditingController notaCtrl;

  void dispose() {
    cantidadCtrl.dispose();
    notaCtrl.dispose();
  }
}

class _PedidoFormScreenState extends State<PedidoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late PedidoTipo _tipo;

  // Campos compartidos / distribución
  final _destinoCtrl = TextEditingController();
  final _destinoLatCtrl = TextEditingController();
  final _destinoLngCtrl = TextEditingController();
  final _origenAlmacenCtrl = TextEditingController();
  final _fechaEntregaCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final List<_DistDraftLineControllers> _distLines = [
    _DistDraftLineControllers(),
  ];
  int? _distPuntoVentaId;
  int? _distAlmacenMayoristaId;
  PedidoDistribucionFormData? _distFormData;

  // Estado para flujo completo Agrícola → Planta (paridad con Web)
  bool _loadingAgricolaForm = false;
  String? _agricolaFormError;
  PedidoAgricolaFormData? _agricolaForm;
  int? _origenAlmacenId;
  final List<int?> _extraRecogidaAlmacenIds = [];
  int? _destinoAlmacenId;
  final _horaRecogidaCtrl = TextEditingController();
  final _instruccionesRecogidaCtrl = TextEditingController();
  final _instruccionesEntregaCtrl = TextEditingController();
  final List<_AgricolaLineDraft> _agricolaLines = [_AgricolaLineDraft()];
  int? _transportistaId;
  int? _vehiculoId;
  final _costoBsCtrl = TextEditingController();
  bool _costoEditadoManual = false;
  bool _calculandoCosto = false;
  PedidoCostoEstimacion? _costoEstimacion;
  PedidoCapacidadValidacion? _capacidadValidacion;
  int _capacidadSeq = 0;

  bool _submitting = false;
  ApiException? _submitError;

  List<PedidoTipo> get _allowedTipos => [
    if (PedidoPermissions.canCreateDistribucion(widget.user))
      PedidoTipo.distribucion,
    if (PedidoPermissions.canCreateAgricola(widget.user)) PedidoTipo.agricola,
  ];

  @override
  void initState() {
    super.initState();
    final allowed = _allowedTipos;
    _tipo = allowed.isNotEmpty ? allowed.first : PedidoTipo.distribucion;
    if (_tipo == PedidoTipo.agricola) {
      unawaited(_loadAgricolaForm());
    } else if (PedidoPermissions.canCreateDistribucion(widget.user)) {
      unawaited(_tryLoadDistribucionForm());
    }
  }

  @override
  void dispose() {
    _destinoCtrl.dispose();
    _destinoLatCtrl.dispose();
    _destinoLngCtrl.dispose();
    _origenAlmacenCtrl.dispose();
    _fechaEntregaCtrl.dispose();
    _observacionesCtrl.dispose();
    _horaRecogidaCtrl.dispose();
    _instruccionesRecogidaCtrl.dispose();
    _instruccionesEntregaCtrl.dispose();
    _costoBsCtrl.dispose();
    for (final line in _distLines) {
      line.dispose();
    }
    for (final line in _agricolaLines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _tryLoadDistribucionForm() async {
    try {
      final data = await widget.service.loadPedidoDistribucionForm(widget.user);
      if (!mounted) return;
      if (data.hasOptions) {
        setState(() {
          _distFormData = data;
          if (data.puntosVenta.length == 1) {
            _distPuntoVentaId = data.puntosVenta.first.id;
            _destinoCtrl.text = '${_distPuntoVentaId!}';
          }
          if (data.almacenesMayoristas.length == 1) {
            _distAlmacenMayoristaId = data.almacenesMayoristas.first.id;
            _origenAlmacenCtrl.text = '${_distAlmacenMayoristaId!}';
          }
        });
      }
    } catch (_) {
      // Mantiene el formulario estándar si el catálogo no está disponible.
    }
  }

  Future<void> _loadAgricolaForm() async {
    setState(() {
      _loadingAgricolaForm = true;
      _agricolaFormError = null;
    });
    try {
      final data = await widget.service.loadPedidoAgricolaForm(widget.user);
      if (!mounted) return;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final defaultDate =
          '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

      setState(() {
        _agricolaForm = data;
        _loadingAgricolaForm = false;
        if (_fechaEntregaCtrl.text.trim().isEmpty) {
          _fechaEntregaCtrl.text = defaultDate;
        }
        if (data.almacenesOrigen.isNotEmpty) {
          _origenAlmacenId ??= data.almacenesOrigen.first.id;
        }
        if (data.almacenesDestino.isNotEmpty) {
          _destinoAlmacenId ??= data.almacenesDestino.first.id;
        }
        if (_agricolaLines.isNotEmpty) {
          _agricolaLines.first.almacenId = _origenAlmacenId;
          _autoSelectFirstProductIfSingle(_agricolaLines.first, data);
        }
        if (data.transportistas.length == 1) {
          _selectTransportistaInternal(data.transportistas.first, data);
        }
      });
      unawaited(_recalculateCosto());
      unawaited(_recalculateCapacidad());
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingAgricolaForm = false;
        _agricolaFormError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAgricolaForm = false;
        _agricolaFormError =
            'No se pudieron cargar almacenes, productos y transportistas para el envío.';
      });
    }
  }

  void _autoSelectFirstProductIfSingle(
    _AgricolaLineDraft line,
    PedidoAgricolaFormData data,
  ) {
    final products = _productsForAlmacen(line.almacenId, data);
    if (products.length == 1 && line.productoRef == null) {
      _applyProductSelection(line, products.first, data);
    }
  }

  List<PedidoProductoAgricolaOption> _productsForAlmacen(
    int? almacenId,
    PedidoAgricolaFormData? data,
  ) {
    if (data == null) return const [];
    if (almacenId == null) return data.productos;
    return data.productos.where((p) => p.almacenId == almacenId).toList();
  }

  PedidoAlmacenOption? _findAlmacen(List<PedidoAlmacenOption> list, int? id) {
    if (id == null) return null;
    for (final item in list) {
      if (item.id == id) return item;
    }
    return null;
  }

  PedidoProductoAgricolaOption? _findProduct(String? ref) {
    final form = _agricolaForm;
    if (form == null || ref == null) return null;
    for (final p in form.productos) {
      if (p.productoRef == ref) return p;
    }
    return null;
  }

  PedidoCalibreOption? _findCalibre(
    PedidoProductoAgricolaOption? product,
    int? calibreId,
  ) {
    if (product == null || calibreId == null) return null;
    for (final c in product.calibres) {
      if (c.id == calibreId) return c;
    }
    return null;
  }

  PedidoTipoEmpaqueOption? _findTipoEmpaque(int? empaqueId) {
    final form = _agricolaForm;
    if (form == null || empaqueId == null) return null;
    for (final e in form.tiposEmpaque) {
      if (e.id == empaqueId) return e;
    }
    return null;
  }

  PedidoTransportistaOption? _findTransportista(int? id) {
    final form = _agricolaForm;
    if (form == null || id == null) return null;
    for (final t in form.transportistas) {
      if (t.id == id) return t;
    }
    return null;
  }

  PedidoVehiculoOption? _findVehiculo(int? id) {
    final form = _agricolaForm;
    if (form == null || id == null) return null;
    for (final v in form.vehiculos) {
      if (v.id == id) return v;
    }
    return null;
  }

  List<PedidoVehiculoOption> _compatibleVehiculos() {
    final form = _agricolaForm;
    if (form == null) return const [];
    final driver = _findTransportista(_transportistaId);
    if (driver == null) return form.vehiculos;
    if (driver.vehiculosCompatibles.isEmpty) return const [];
    final allowed = driver.vehiculosCompatibles.toSet();
    return form.vehiculos.where((v) => allowed.contains(v.id)).toList();
  }

  void _applyProductSelection(
    _AgricolaLineDraft line,
    PedidoProductoAgricolaOption product,
    PedidoAgricolaFormData data,
  ) {
    line.productoRef = product.productoRef;
    line.partidaId = product.partidas.length == 1
        ? product.partidas.first.id
        : null;
    final defaultCalibre =
        _findCalibre(product, product.calibreDefaultId) ??
        (product.calibres.isNotEmpty ? product.calibres.first : null);
    line.calibreId = defaultCalibre?.id;
    final empaqueId =
        defaultCalibre?.tipoEmpaqueId ??
        (data.tiposEmpaque.isNotEmpty ? data.tiposEmpaque.first.id : null);
    line.tipoEmpaqueId = empaqueId;
  }

  void _selectTransportistaInternal(
    PedidoTransportistaOption driver,
    PedidoAgricolaFormData data,
  ) {
    _transportistaId = driver.id;
    final allowed = driver.vehiculosCompatibles.toSet();
    if (_vehiculoId != null && allowed.contains(_vehiculoId)) {
      return;
    }
    if (driver.vehiculoDefaultId != null &&
        allowed.contains(driver.vehiculoDefaultId)) {
      _vehiculoId = driver.vehiculoDefaultId;
      return;
    }
    final firstCompatible = data.vehiculos.where((v) => allowed.contains(v.id));
    _vehiculoId = firstCompatible.isNotEmpty ? firstCompatible.first.id : null;
  }

  double _computedLineKg(_AgricolaLineDraft line) {
    final raw = double.tryParse(
      line.cantidadCtrl.text.trim().replaceAll(',', '.'),
    );
    if (raw == null || raw <= 0) return 0;
    final product = _findProduct(line.productoRef);
    final calibre = _findCalibre(product, line.calibreId);
    switch (line.forma) {
      case _FormaPedidoAgricola.kg:
        return raw;
      case _FormaPedidoAgricola.empaques:
        final pesoEmp = calibre?.pesoPorEmpaqueKg ?? 0;
        return pesoEmp > 0 ? (raw * pesoEmp) : raw;
      case _FormaPedidoAgricola.unidades:
        final pesoUnd = calibre?.pesoPromedioKg ?? 0;
        return pesoUnd > 0 ? (raw * pesoUnd) : raw;
    }
  }

  int _computedLineEmpaques(_AgricolaLineDraft line, double kg) {
    final raw = double.tryParse(
      line.cantidadCtrl.text.trim().replaceAll(',', '.'),
    );
    if (raw == null || raw <= 0) return 0;
    if (line.forma == _FormaPedidoAgricola.empaques) return raw.ceil();
    final product = _findProduct(line.productoRef);
    final calibre = _findCalibre(product, line.calibreId);
    final pesoEmp = calibre?.pesoPorEmpaqueKg ?? 0;
    if (pesoEmp <= 0) return 0;
    return math.max(1, (kg / pesoEmp).ceil());
  }

  int _computedLineUnidades(_AgricolaLineDraft line, double kg) {
    final raw = double.tryParse(
      line.cantidadCtrl.text.trim().replaceAll(',', '.'),
    );
    if (raw == null || raw <= 0) return 0;
    if (line.forma == _FormaPedidoAgricola.unidades) return raw.round();
    final product = _findProduct(line.productoRef);
    final calibre = _findCalibre(product, line.calibreId);
    final pesoUnd = calibre?.pesoPromedioKg ?? 0;
    if (pesoUnd <= 0) return 0;
    return (kg / pesoUnd).round();
  }

  double get _totalAgricolaKg {
    var total = 0.0;
    for (final line in _agricolaLines) {
      total += _computedLineKg(line);
    }
    return total;
  }

  double get _totalAgricolaVolumenM3 => _totalAgricolaKg / 200.0;

  String _formatKg(double kg) {
    if (kg == kg.roundToDouble()) return kg.toStringAsFixed(0);
    return kg.toStringAsFixed(2);
  }

  String? _buildMetaObservaciones(_AgricolaLineDraft line) {
    final rawText = line.cantidadCtrl.text.trim().replaceAll(',', '.');
    final product = _findProduct(line.productoRef);
    final calibre = _findCalibre(product, line.calibreId);
    final empaque = _findTipoEmpaque(line.tipoEmpaqueId);
    final empaqueNombre =
        empaque?.nombre ?? calibre?.tipoEmpaqueNombre ?? 'Caja';
    final calibreNombre = calibre?.nombre;

    String? meta;
    if (rawText.isNotEmpty) {
      switch (line.forma) {
        case _FormaPedidoAgricola.empaques:
          meta = '$rawText empaques · $empaqueNombre';
          if (calibreNombre != null) meta = '$meta · $calibreNombre';
        case _FormaPedidoAgricola.unidades:
          meta = '$rawText unidades';
          if (calibreNombre != null) meta = '$meta · $calibreNombre';
        case _FormaPedidoAgricola.kg:
          meta = '$rawText kg · $empaqueNombre';
          if (calibreNombre != null) meta = '$meta · $calibreNombre';
      }
    }

    final note = line.notaCtrl.text.trim();
    if (meta == null) return note.isEmpty ? null : note;
    final block = '@carga:$meta@';
    return note.isEmpty ? block : '$block $note';
  }

  Future<void> _recalculateCosto() async {
    final form = _agricolaForm;
    if (form == null) return;
    final origen = _findAlmacen(form.almacenesOrigen, _origenAlmacenId);
    final destino = _findAlmacen(form.almacenesDestino, _destinoAlmacenId);
    if (origen == null || destino == null) return;

    final paradas = <Map<String, double>>[
      {'lat': origen.lat, 'lng': origen.lng},
      for (final extraId in _extraRecogidaAlmacenIds)
        if (_findAlmacen(form.almacenesOrigen, extraId) case final extra?)
          {'lat': extra.lat, 'lng': extra.lng},
      {'lat': destino.lat, 'lng': destino.lng},
    ];

    setState(() => _calculandoCosto = true);
    try {
      final result = await widget.service.calcularCostoPedidoAgricola(
        widget.user,
        paradas: paradas,
      );
      if (!mounted) return;
      setState(() {
        _calculandoCosto = false;
        _costoEstimacion = result;
        if (!_costoEditadoManual && result.costoBs > 0) {
          _costoBsCtrl.text = '${result.costoBs}';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _calculandoCosto = false);
    }
  }

  Future<void> _recalculateCapacidad() async {
    final vehiculoId = _vehiculoId;
    final pesoKg = _totalAgricolaKg;
    if (vehiculoId == null || pesoKg <= 0) {
      if (mounted && _capacidadValidacion != null) {
        setState(() => _capacidadValidacion = null);
      }
      return;
    }
    final seq = ++_capacidadSeq;
    try {
      final result = await widget.service.validarCapacidadPedidoAgricola(
        widget.user,
        vehiculoId: vehiculoId,
        pesoKg: double.parse(pesoKg.toStringAsFixed(2)),
        volumenM3: double.parse(_totalAgricolaVolumenM3.toStringAsFixed(2)),
      );
      if (!mounted || seq != _capacidadSeq) return;
      setState(() => _capacidadValidacion = result);
    } catch (_) {
      // Usa cálculo local de respaldo si la consulta remota falla.
    }
  }

  Future<void> _pickFechaEntrega() async {
    final initial =
        DateTime.tryParse(_fechaEntregaCtrl.text.trim()) ??
        DateTime.now().add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    final formatted =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() => _fechaEntregaCtrl.text = formatted);
    _clearError(
      field: _tipo == PedidoTipo.distribucion
          ? 'fecha_entrega_deseada'
          : 'fechaEntregaDeseada',
    );
  }

  Future<void> _pickHoraRecogida() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    setState(() => _horaRecogidaCtrl.text = '$hh:$mm');
  }

  String? _fieldError(String field) {
    final messages = _submitError?.validationErrors[field];
    return messages == null || messages.isEmpty ? null : messages.join('\n');
  }

  void _clearError({String? field}) {
    final error = _submitError;
    if (error == null) return;
    if (field != null && error.validationErrors.isNotEmpty) {
      if (!error.validationErrors.containsKey(field)) return;
      final remaining = Map.of(error.validationErrors)..remove(field);
      setState(() {
        _submitError = remaining.isEmpty
            ? null
            : ApiException(
                error.message,
                statusCode: error.statusCode,
                validationErrors: remaining,
              );
      });
    } else {
      setState(() => _submitError = null);
    }
  }

  Map<String, dynamic> _buildPayload() {
    if (_tipo == PedidoTipo.distribucion) {
      final detalles = <Map<String, dynamic>>[];
      for (final line in _distLines) {
        final partida = int.tryParse(line.partida.text.trim());
        detalles.add({
          'insumoid':
              line.selectedProductoId ?? int.parse(line.producto.text.trim()),
          'insumo_presentacionid':
              line.selectedPresentacionId ??
              int.parse(line.presentacion.text.trim()),
          'cantidad': line.cantidad.text.trim().replaceAll(',', '.'),
          if (partida != null && partida > 0)
            'inventario_presentacion_loteid': partida,
        });
      }
      final almacenOrigen =
          _distAlmacenMayoristaId ??
          int.tryParse(_origenAlmacenCtrl.text.trim());
      return {
        'puntoventaid':
            _distPuntoVentaId ?? int.parse(_destinoCtrl.text.trim()),
        'fecha_entrega_deseada': _fechaEntregaCtrl.text.trim(),
        if (almacenOrigen != null && almacenOrigen > 0)
          'almacen_mayorista_origenid': almacenOrigen,
        if (_observacionesCtrl.text.trim().isNotEmpty)
          'observaciones': _observacionesCtrl.text.trim(),
        'detalles': detalles,
      };
    }

    final form = _agricolaForm!;
    final origen = _findAlmacen(form.almacenesOrigen, _origenAlmacenId)!;
    final destino = _findAlmacen(form.almacenesDestino, _destinoAlmacenId)!;

    final recogidas = <Map<String, dynamic>>[];
    for (final extraId in _extraRecogidaAlmacenIds) {
      final alm = _findAlmacen(form.almacenesOrigen, extraId);
      if (alm != null) {
        recogidas.add({
          'almacenid': alm.id,
          'latitud': alm.lat,
          'longitud': alm.lng,
          'direccion': alm.direccion,
        });
      }
    }

    final detalles = <Map<String, dynamic>>[];
    for (final line in _agricolaLines) {
      final product = _findProduct(line.productoRef)!;
      final kg = _computedLineKg(line);
      final kgStr = double.parse(kg.toStringAsFixed(2)).toString();
      final metaObs = _buildMetaObservaciones(line);

      int? validCalibreId;
      if (line.calibreId != null) {
        if (product.tipo == 'cosecha') {
          if (product.calibreDefaultId != null &&
              line.calibreId == product.calibreDefaultId) {
            validCalibreId = line.calibreId;
          }
        } else {
          final calibre = _findCalibre(product, line.calibreId);
          if (calibre != null &&
              product.insumoId != null &&
              calibre.idProducto == product.insumoId) {
            validCalibreId = calibre.id;
          }
        }
      }

      detalles.add({
        'producto_ref': product.productoRef,
        'cantidad': kgStr,
        'catalogotamanoconteoid': ?validCalibreId,
        'materiaprimaloteid': ?line.partidaId,
        'observaciones': ?metaObs,
      });
    }

    return {
      'origen_almacenid': origen.id,
      'origen_latitud': origen.lat,
      'origen_longitud': origen.lng,
      'origen_direccion': '${origen.nombre} · ${origen.direccion}',
      'latitud': destino.lat,
      'longitud': destino.lng,
      'direccion_texto': '${destino.nombre} · ${destino.direccion}',
      'fechaEntregaDeseada': _fechaEntregaCtrl.text.trim(),
      if (_horaRecogidaCtrl.text.trim().isNotEmpty)
        'hora_recogida': _horaRecogidaCtrl.text.trim(),
      if (_instruccionesRecogidaCtrl.text.trim().isNotEmpty)
        'instrucciones_recogida': _instruccionesRecogidaCtrl.text.trim(),
      if (_instruccionesEntregaCtrl.text.trim().isNotEmpty)
        'instrucciones_entrega': _instruccionesEntregaCtrl.text.trim(),
      if (_observacionesCtrl.text.trim().isNotEmpty)
        'observaciones': _observacionesCtrl.text.trim(),
      'transportista_usuarioid': _transportistaId!,
      'vehiculoid': _vehiculoId!,
      'costo_bs': int.parse(_costoBsCtrl.text.trim()),
      if (recogidas.isNotEmpty) 'recogidas': recogidas,
      'detalles': detalles,
    };
  }

  String? _validateAgricolaExtra() {
    final form = _agricolaForm;
    if (form == null) return 'Espera a que terminen de cargar los catálogos.';
    if (_origenAlmacenId == null) {
      return 'Selecciona el almacén agrícola de recogida.';
    }
    if (_destinoAlmacenId == null) {
      return 'Selecciona el almacén de planta destino.';
    }
    if (_agricolaLines.isEmpty) {
      return 'Agrega al menos un producto para el envío.';
    }
    for (var i = 0; i < _agricolaLines.length; i++) {
      final line = _agricolaLines[i];
      final product = _findProduct(line.productoRef);
      if (product == null) {
        return 'Selecciona el producto en la línea #${i + 1}.';
      }
      final kg = _computedLineKg(line);
      if (kg <= 0) {
        return 'Indica una cantidad mayor a cero en la línea #${i + 1}.';
      }
      if (kg > product.stockKg + 0.0001) {
        return 'La línea #${i + 1} (${_formatKg(kg)} kg) supera el stock disponible (${_formatKg(product.stockKg)} kg).';
      }
      if (product.tipo == 'insumo' &&
          product.partidas.isNotEmpty &&
          line.partidaId == null) {
        return 'Selecciona la partida de material en la línea #${i + 1}.';
      }
    }
    if (_transportistaId == null) {
      return 'Selecciona el chofer para el envío.';
    }
    if (_vehiculoId == null) {
      return 'Selecciona un vehículo compatible para el chofer.';
    }
    final vehiculo = _findVehiculo(_vehiculoId);
    if (vehiculo != null &&
        vehiculo.capacidadKg > 0 &&
        _totalAgricolaKg > vehiculo.capacidadKg + 0.0001) {
      return 'La carga total (${_formatKg(_totalAgricolaKg)} kg) supera la capacidad del vehículo ${vehiculo.placa} (${vehiculo.capacidadKg.toStringAsFixed(0)} kg).';
    }
    if (_capacidadValidacion != null && !_capacidadValidacion!.ok) {
      return _capacidadValidacion!.mensaje.isNotEmpty
          ? _capacidadValidacion!.mensaje
          : 'La carga supera la capacidad del vehículo seleccionado.';
    }
    final costo = int.tryParse(_costoBsCtrl.text.trim());
    if (costo == null || costo <= 0) {
      return 'Indica un costo del servicio en bolivianos mayor a 0.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!validateForm(_formKey)) return;

    if (_tipo == PedidoTipo.agricola) {
      final extraError = _validateAgricolaExtra();
      if (extraError != null) {
        setState(() => _submitError = ApiException(extraError));
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final created = await widget.service.createPedidoMovil(
        widget.user,
        tipo: _tipo,
        body: _buildPayload(),
      );
      if (!mounted) return;
      widget.onPedidoCreated?.call();
      Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.pedido(created.tipo, created.id));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error;
      });
      revealFormErrors(_formKey);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = const ApiException(
          'No se pudo registrar el envío. Tus datos se conservaron para reintentar.',
        );
      });
    }
  }

  /// Quita un elemento de una lista del formulario y deja 5 s para deshacer.
  /// El borrador solo se libera cuando ya no se puede recuperar.
  void _removeUndoable<T>(
    List<T> list,
    int index,
    String message, {
    void Function(T item)? dispose,
    VoidCallback? after,
  }) {
    final removed = list[index];
    setState(() => list.removeAt(index));
    after?.call();
    var undone = false;
    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: 'Deshacer',
              onPressed: () {
                if (!mounted || undone) return;
                undone = true;
                setState(
                  () => list.insert(index.clamp(0, list.length), removed),
                );
                after?.call();
              },
            ),
          ),
        )
        .closed
        .then((_) {
          if (!undone) dispose?.call(removed);
        });
  }

  @override
  Widget build(BuildContext context) {
    if (!PedidoPermissions.canCreateAny(widget.user)) {
      return ModuleAccessDenied(
        title: 'Nuevo envío',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    final isAgricola = _tipo == PedidoTipo.agricola;

    return Scaffold(
      appBar: AppBar(title: Text(isAgricola ? 'Nuevo envío' : 'Nuevo pedido')),
      body: SafeArea(
        child: isAgricola
            ? _buildAgricolaBody(context)
            : _buildDistribucionBody(context),
      ),
    );
  }

  Widget _buildAgricolaBody(BuildContext context) {
    if (_loadingAgricolaForm) {
      return const AppLoading(
        message: 'Cargando almacenes, productos y flota disponible...',
      );
    }
    if (_agricolaFormError != null || _agricolaForm == null) {
      return AppErrorState(
        message:
            _agricolaFormError ??
            'No se pudieron cargar los datos para crear el envío.',
        onRetry: _loadAgricolaForm,
      );
    }

    final form = _agricolaForm!;
    final look = AppModule.pedidos.look;
    final scrollPadding = formScrollPadding(context);
    final allowed = _allowedTipos;
    final origen = _findAlmacen(form.almacenesOrigen, _origenAlmacenId);
    final destino = _findAlmacen(form.almacenesDestino, _destinoAlmacenId);
    final driver = _findTransportista(_transportistaId);
    final vehiculo = _findVehiculo(_vehiculoId);
    final compatibleVehiculos = _compatibleVehiculos();
    final totalKg = _totalAgricolaKg;
    final totalVolM3 = _totalAgricolaVolumenM3;

    final allErrors = <String>[];
    if (_submitError != null) {
      if (_submitError!.validationErrors.isNotEmpty) {
        for (final entry in _submitError!.validationErrors.entries) {
          allErrors.addAll(entry.value);
        }
      } else {
        allErrors.add(_submitError!.message);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (allowed.length > 1) ...[
                  _buildTipoSelector(allowed, look),
                  const SizedBox(height: 18),
                ],

                // PASO 1: RUTA Y HORARIOS
                SectionTitle('1. Ruta y horarios', color: look.tone),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('pedido.fecha_entrega'),
                  controller: _fechaEntregaCtrl,
                  scrollPadding: scrollPadding,
                  readOnly: true,
                  enabled: !_submitting,
                  onTap: _submitting ? null : _pickFechaEntrega,
                  forceErrorText: _fieldError('fechaEntregaDeseada'),
                  decoration: const InputDecoration(
                    labelText: 'Fecha de entrega deseada *',
                    prefixIcon: Icon(Icons.event_outlined),
                    suffixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return 'Indica la fecha de entrega deseada.';
                    }
                    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
                      return 'Usa el formato AAAA-MM-DD.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('pedido.hora_recogida'),
                  controller: _horaRecogidaCtrl,
                  scrollPadding: scrollPadding,
                  readOnly: true,
                  enabled: !_submitting,
                  onTap: _submitting ? null : _pickHoraRecogida,
                  decoration: InputDecoration(
                    labelText: 'Hora de recogida (opcional)',
                    prefixIcon: const Icon(Icons.schedule_rounded),
                    suffixIcon: _horaRecogidaCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Limpiar hora',
                            onPressed: _submitting
                                ? null
                                : () => setState(_horaRecogidaCtrl.clear),
                            icon: const Icon(Icons.close_rounded),
                          )
                        : const Icon(Icons.access_time_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                if (form.almacenesOrigen.isEmpty)
                  const AppNotice(
                    tone: AppNoticeTone.error,
                    message:
                        'No tienes almacenes agrícolas activos asignados para despachar envíos.',
                  )
                else
                  DropdownButtonFormField<int>(
                    key: const ValueKey('pedido.almacen_origen_select'),
                    initialValue: _origenAlmacenId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Almacén agrícola de recogida *',
                      prefixIcon: Icon(Icons.warehouse_outlined),
                    ),
                    items: [
                      for (final alm in form.almacenesOrigen)
                        DropdownMenuItem<int>(
                          value: alm.id,
                          child: Text(
                            '${alm.nombre} · ${alm.direccion}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            setState(() {
                              _origenAlmacenId = value;
                              if (_agricolaLines.isNotEmpty) {
                                _agricolaLines.first.almacenId = value;
                                final avail = _productsForAlmacen(value, form);
                                if (!avail.any(
                                  (p) =>
                                      p.productoRef ==
                                      _agricolaLines.first.productoRef,
                                )) {
                                  _agricolaLines.first.productoRef = null;
                                  _agricolaLines.first.calibreId = null;
                                  _agricolaLines.first.partidaId = null;
                                  _autoSelectFirstProductIfSingle(
                                    _agricolaLines.first,
                                    form,
                                  );
                                }
                              }
                            });
                            _clearError(field: 'origen_almacenid');
                            unawaited(_recalculateCosto());
                          },
                    validator: (value) => value == null
                        ? 'Selecciona el almacén de recogida.'
                        : null,
                  ),
                if (form.almacenesOrigen.length > 1) ...[
                  const SizedBox(height: 8),
                  for (var r = 0; r < _extraRecogidaAlmacenIds.length; r++) ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('pedido.recogida_extra.$r'),
                            initialValue: _extraRecogidaAlmacenIds[r],
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Recogida adicional #${r + 2}',
                              prefixIcon: const Icon(
                                Icons.add_location_alt_outlined,
                              ),
                            ),
                            items: [
                              for (final alm in form.almacenesOrigen)
                                DropdownMenuItem<int>(
                                  value: alm.id,
                                  child: Text(
                                    alm.nombre,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _submitting
                                ? null
                                : (val) {
                                    setState(() {
                                      _extraRecogidaAlmacenIds[r] = val;
                                      final lineIdx = r + 1;
                                      if (lineIdx < _agricolaLines.length) {
                                        _agricolaLines[lineIdx].almacenId = val;
                                      }
                                    });
                                    unawaited(_recalculateCosto());
                                  },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar recogida',
                          onPressed: _submitting
                              ? null
                              : () => _removeUndoable(
                                  _extraRecogidaAlmacenIds,
                                  r,
                                  'Recogida quitada',
                                  after: () => unawaited(_recalculateCosto()),
                                ),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _submitting
                          ? null
                          : () {
                              setState(() {
                                _extraRecogidaAlmacenIds.add(null);
                              });
                            },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Agregar otro punto de recogida'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (form.almacenesDestino.isEmpty)
                  const AppNotice(
                    tone: AppNoticeTone.error,
                    message:
                        'No hay almacenes de planta activos registrados como destino.',
                  )
                else
                  DropdownButtonFormField<int>(
                    key: const ValueKey('pedido.almacen_destino_select'),
                    initialValue: _destinoAlmacenId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Planta destino *',
                      prefixIcon: Icon(Icons.factory_outlined),
                    ),
                    items: [
                      for (final alm in form.almacenesDestino)
                        DropdownMenuItem<int>(
                          value: alm.id,
                          child: Text(
                            alm.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            setState(() => _destinoAlmacenId = value);
                            _clearError(field: 'latitud');
                            unawaited(_recalculateCosto());
                          },
                    validator: (value) =>
                        value == null ? 'Selecciona la planta destino.' : null,
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('pedido.instrucciones_recogida'),
                  controller: _instruccionesRecogidaCtrl,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Instrucciones de recogida (opcional)',
                    prefixIcon: Icon(Icons.outbox_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('pedido.instrucciones_entrega'),
                  controller: _instruccionesEntregaCtrl,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Instrucciones de entrega en planta (opcional)',
                    prefixIcon: Icon(Icons.move_to_inbox_outlined),
                  ),
                ),

                // PASO 2: CARGA Y PRODUCTOS
                const SizedBox(height: 24),
                SectionTitle('2. Carga y productos', color: look.tone),
                const SizedBox(height: 12),
                if (form.productos.isEmpty)
                  const AppNotice(
                    tone: AppNoticeTone.info,
                    message:
                        'No hay cosechas ni semillas con stock disponible en tus almacenes agrícolas. Primero registra una cosecha o stock en almacén.',
                  )
                else ...[
                  for (var i = 0; i < _agricolaLines.length; i++) ...[
                    _agricolaLineCard(i, form, scrollPadding),
                    const SizedBox(height: 12),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('pedido.agregar_linea'),
                      onPressed: _submitting
                          ? null
                          : () {
                              setState(() {
                                final extraIdx = _agricolaLines.length - 1;
                                final almId =
                                    extraIdx < _extraRecogidaAlmacenIds.length
                                    ? (_extraRecogidaAlmacenIds[extraIdx] ??
                                          _origenAlmacenId)
                                    : _origenAlmacenId;
                                _agricolaLines.add(
                                  _AgricolaLineDraft(almacenId: almId),
                                );
                              });
                            },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Agregar otro producto'),
                    ),
                  ),
                ],

                // PASO 3: TRANSPORTE Y COSTO
                const SizedBox(height: 24),
                SectionTitle('3. Chofer, vehículo y costo', color: look.tone),
                const SizedBox(height: 12),
                if (form.transportistas.isEmpty)
                  const AppNotice(
                    tone: AppNoticeTone.error,
                    message:
                        'No hay transportistas de flota agrícola disponibles en este momento.',
                  )
                else
                  DropdownButtonFormField<int>(
                    key: const ValueKey('pedido.transportista_select'),
                    initialValue: _transportistaId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Chofer asignado *',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    items: [
                      for (final t in form.transportistas)
                        DropdownMenuItem<int>(
                          value: t.id,
                          child: Text(
                            t.licencias.isNotEmpty
                                ? '${t.nombre} · Lic. ${t.licencias.join(", ")}'
                                : t.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            final selected = _findTransportista(value);
                            setState(() {
                              if (selected != null) {
                                _selectTransportistaInternal(selected, form);
                              } else {
                                _transportistaId = null;
                                _vehiculoId = null;
                              }
                            });
                            _clearError(field: 'transportista_usuarioid');
                            unawaited(_recalculateCapacidad());
                          },
                    validator: (value) =>
                        value == null ? 'Selecciona un chofer.' : null,
                  ),
                const SizedBox(height: 12),
                if (compatibleVehiculos.isEmpty)
                  AppNotice(
                    tone: AppNoticeTone.error,
                    message: _transportistaId == null
                        ? 'No hay vehículos agrícolas operativos disponibles.'
                        : 'El chofer seleccionado no tiene vehículos compatibles disponibles.',
                  )
                else
                  DropdownButtonFormField<int>(
                    key: const ValueKey('pedido.vehiculo_select'),
                    initialValue:
                        compatibleVehiculos.any((v) => v.id == _vehiculoId)
                        ? _vehiculoId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vehículo *',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    items: [
                      for (final v in compatibleVehiculos)
                        DropdownMenuItem<int>(
                          value: v.id,
                          child: Text(
                            v.displayLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            setState(() => _vehiculoId = value);
                            _clearError(field: 'vehiculoid');
                            unawaited(_recalculateCapacidad());
                          },
                    validator: (value) =>
                        value == null ? 'Selecciona un vehículo.' : null,
                  ),
                if (vehiculo != null && totalKg > 0) ...[
                  const SizedBox(height: 12),
                  _capacityPreviewCard(vehiculo, totalKg, totalVolM3),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('pedido.costo_bs'),
                  controller: _costoBsCtrl,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  forceErrorText: _fieldError('costo_bs'),
                  decoration: InputDecoration(
                    labelText: 'Costo del servicio (Bs) *',
                    prefixIcon: const Icon(Icons.payments_outlined),
                    suffixText: 'Bs',
                    helperText: _calculandoCosto
                        ? 'Calculando costo estimado por distancia...'
                        : (_costoEstimacion?.detalle.isNotEmpty == true
                              ? _costoEstimacion!.detalle
                              : 'Se estima automáticamente según la ruta.'),
                  ),
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Indica un costo entero mayor a 0 Bs.';
                    }
                    return null;
                  },
                  onChanged: (_) {
                    _costoEditadoManual = true;
                    _clearError(field: 'costo_bs');
                    setState(() {});
                  },
                ),

                // PASO 4: RESUMEN Y CONFIRMACIÓN
                const SizedBox(height: 24),
                SectionTitle('4. Resumen y confirmación', color: look.tone),
                const SizedBox(height: 12),
                _agricolaSummaryCard(
                  origen: origen,
                  destino: destino,
                  driver: driver,
                  vehiculo: vehiculo,
                  totalKg: totalKg,
                  totalVolM3: totalVolM3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('pedido.observaciones'),
                  controller: _observacionesCtrl,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones generales (opcional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),

                if (allErrors.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  AppNotice(
                    tone: AppNoticeTone.error,
                    message: allErrors.join('\n'),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('pedido.guardar'),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _submitting
                        ? 'Registrando envío...'
                        : 'Confirmar y crear envío',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _agricolaLineCard(
    int index,
    PedidoAgricolaFormData form,
    EdgeInsets scrollPadding,
  ) {
    final line = _agricolaLines[index];
    final availableProducts = _productsForAlmacen(
      line.almacenId ?? _origenAlmacenId,
      form,
    );
    final selectedProduct = _findProduct(line.productoRef);
    final computedKg = _computedLineKg(line);
    final computedEmpaques = _computedLineEmpaques(line, computedKg);
    final computedUnidades = _computedLineUnidades(line, computedKg);
    final excedeStock =
        selectedProduct != null &&
        computedKg > selectedProduct.stockKg + 0.0001;
    final hasCalibre = selectedProduct?.calibres.isNotEmpty == true;
    final selectedCalibre = _findCalibre(selectedProduct, line.calibreId);

    return Container(
      key: ValueKey('pedido.linea.$index'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: excedeStock ? AppTheme.clay : AppTheme.ink,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Producto #${index + 1}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (_agricolaLines.length > 1)
                IconButton(
                  tooltip: 'Quitar producto',
                  onPressed: _submitting
                      ? null
                      : () => _removeUndoable(
                          _agricolaLines,
                          index,
                          'Producto quitado',
                          dispose: (line) => line.dispose(),
                          after: () => unawaited(_recalculateCapacidad()),
                        ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('pedido.linea.$index.producto_select'),
            initialValue:
                availableProducts.any((p) => p.productoRef == line.productoRef)
                ? line.productoRef
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Producto en almacén *',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
            items: [
              for (final p in availableProducts)
                DropdownMenuItem<String>(
                  value: p.productoRef,
                  child: Text(
                    '${p.label} (${_formatKg(p.stockKg)} kg disp.)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    setState(() {
                      if (value != null) {
                        final prod = _findProduct(value);
                        if (prod != null) {
                          _applyProductSelection(line, prod, form);
                        }
                      } else {
                        line.productoRef = null;
                        line.calibreId = null;
                        line.partidaId = null;
                      }
                    });
                    _clearError(field: 'detalles.$index.producto_ref');
                    unawaited(_recalculateCapacidad());
                  },
            validator: (value) =>
                value == null ? 'Selecciona un producto.' : null,
          ),
          if (selectedProduct != null &&
              selectedProduct.tipo == 'insumo' &&
              selectedProduct.partidas.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              key: ValueKey('pedido.linea.$index.partida_select'),
              initialValue: line.partidaId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Partida de material *',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
              ),
              items: [
                for (final part in selectedProduct.partidas)
                  DropdownMenuItem<int>(
                    value: part.id,
                    child: Text(
                      '${part.label} (${_formatKg(part.cantidadDisponible)} disp.)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (val) => setState(() => line.partidaId = val),
              validator: (val) =>
                  val == null ? 'Selecciona la partida a usar.' : null,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Forma de indicar la carga',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final forma in _FormaPedidoAgricola.values)
                ChoiceChip(
                  key: ValueKey('pedido.linea.$index.forma.${forma.value}'),
                  label: Text(forma.label),
                  selected: line.forma == forma,
                  selectedColor: AppTheme.maize,
                  backgroundColor: AppTheme.surface,
                  onSelected: _submitting
                      ? null
                      : (_) {
                          setState(() => line.forma = forma);
                          unawaited(_recalculateCapacidad());
                        },
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (form.tiposEmpaque.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              key: ValueKey('pedido.linea.$index.empaque_select'),
              initialValue:
                  form.tiposEmpaque.any((e) => e.id == line.tipoEmpaqueId)
                  ? line.tipoEmpaqueId
                  : form.tiposEmpaque.first.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tipo de empaque *',
                prefixIcon: Icon(Icons.all_inbox_outlined),
              ),
              items: [
                for (final e in form.tiposEmpaque)
                  DropdownMenuItem<int>(
                    value: e.id,
                    child: Text(e.nombre, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (val) => setState(() => line.tipoEmpaqueId = val),
            ),
            const SizedBox(height: 10),
          ],
          if (hasCalibre) ...[
            DropdownButtonFormField<int>(
              key: ValueKey('pedido.linea.$index.calibre_select'),
              initialValue:
                  selectedProduct!.calibres.any((c) => c.id == line.calibreId)
                  ? line.calibreId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText:
                    selectedProduct.tipo == 'cosecha' &&
                        selectedProduct.calibreDefaultId != null
                    ? 'Calibre / presentación (definido en cosecha)'
                    : 'Calibre / tamaño',
                prefixIcon: const Icon(Icons.straighten_rounded),
              ),
              items: [
                for (final c in selectedProduct.calibres)
                  DropdownMenuItem<int>(
                    value: c.id,
                    child: Text(
                      c.pesoPorEmpaqueKg > 0
                          ? '${c.nombre} (${c.conteoPorEmpaque} u/emp · ~${c.pesoPorEmpaqueKg.toStringAsFixed(1)} kg)'
                          : c.nombre,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged:
                  _submitting ||
                      (selectedProduct.tipo == 'cosecha' &&
                          selectedProduct.calibreDefaultId != null)
                  ? null
                  : (val) {
                      setState(() {
                        line.calibreId = val;
                        final cal = _findCalibre(selectedProduct, val);
                        if (cal?.tipoEmpaqueId != null) {
                          line.tipoEmpaqueId = cal!.tipoEmpaqueId;
                        }
                      });
                      unawaited(_recalculateCapacidad());
                    },
            ),
            const SizedBox(height: 10),
          ],
          TextFormField(
            key: ValueKey('pedido.linea.$index.cantidad'),
            controller: line.cantidadCtrl,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            forceErrorText: _fieldError('detalles.$index.cantidad'),
            decoration: InputDecoration(
              labelText: switch (line.forma) {
                _FormaPedidoAgricola.kg => 'Cantidad (kg) *',
                _FormaPedidoAgricola.empaques => 'Cantidad de empaques *',
                _FormaPedidoAgricola.unidades => 'Cantidad de unidades *',
              },
              suffixText: switch (line.forma) {
                _FormaPedidoAgricola.kg => 'kg',
                _FormaPedidoAgricola.empaques => 'emp.',
                _FormaPedidoAgricola.unidades => 'und.',
              },
              helperText: selectedProduct != null
                  ? 'Disponible: ${_formatKg(selectedProduct.stockKg)} kg'
                  : null,
            ),
            validator: (value) => validatePedidoQuantity(
              value,
              unitLabel: line.forma.label.toLowerCase(),
            ),
            onChanged: (_) {
              _clearError(field: 'detalles.$index.cantidad');
              setState(() {});
              unawaited(_recalculateCapacidad());
            },
          ),
          if (computedKg > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: excedeStock
                    ? const Color(0xFFFDECE8)
                    : AppTheme.sprout.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: excedeStock ? AppTheme.clay : AppTheme.forest,
                ),
              ),
              child: Text(
                excedeStock
                    ? 'Supera el stock disponible: ${_formatKg(computedKg)} kg pedidos vs ${_formatKg(selectedProduct.stockKg)} kg disponibles.'
                    : [
                        'Peso total: ${_formatKg(computedKg)} kg',
                        if (computedEmpaques > 0)
                          '~$computedEmpaques ${_findTipoEmpaque(line.tipoEmpaqueId)?.nombre ?? selectedCalibre?.tipoEmpaqueNombre ?? "empaques"}',
                        if (computedUnidades > 0) '~$computedUnidades unidades',
                      ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: excedeStock ? AppTheme.clay : AppTheme.forest,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('pedido.linea.$index.nota'),
            controller: line.notaCtrl,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'Nota del producto (opcional)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _capacityPreviewCard(
    PedidoVehiculoOption vehiculo,
    double totalKg,
    double totalVolM3,
  ) {
    final pctPeso =
        _capacidadValidacion?.porcentajePeso ??
        (vehiculo.capacidadKg > 0 ? (totalKg / vehiculo.capacidadKg) * 100 : 0);
    final pctVol =
        _capacidadValidacion?.porcentajeVolumen ??
        (vehiculo.capacidadM3 > 0
            ? (totalVolM3 / vehiculo.capacidadM3) * 100
            : 0);
    final ok =
        (_capacidadValidacion?.ok ?? true) &&
        (vehiculo.capacidadKg <= 0 ||
            totalKg <= vehiculo.capacidadKg + 0.0001) &&
        (vehiculo.capacidadM3 <= 0 ||
            totalVolM3 <= vehiculo.capacidadM3 + 0.0001);

    Color barColor(double pct) {
      if (pct > 100) return AppTheme.clay;
      if (pct >= 85) return const Color(0xFFB45309);
      return AppTheme.forest;
    }

    return Container(
      key: const ValueKey('pedido.capacidad_preview'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: ok ? AppTheme.ink : AppTheme.clay,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ocupación del vehículo ${vehiculo.placa}',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Peso: ${_formatKg(totalKg)} / ${vehiculo.capacidadKg.toStringAsFixed(0)} kg',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '${pctPeso.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: barColor(pctPeso),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (pctPeso / 100).clamp(0.0, 1.0),
            color: barColor(pctPeso),
            backgroundColor: AppTheme.border,
          ),
          if (vehiculo.capacidadM3 > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Volumen est.: ${totalVolM3.toStringAsFixed(2)} / ${vehiculo.capacidadM3.toStringAsFixed(1)} m³',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${pctVol.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: barColor(pctVol),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (pctVol / 100).clamp(0.0, 1.0),
              color: barColor(pctVol),
              backgroundColor: AppTheme.border,
            ),
          ],
          if (!ok) ...[
            const SizedBox(height: 8),
            Text(
              _capacidadValidacion?.mensaje.isNotEmpty == true
                  ? _capacidadValidacion!.mensaje
                  : 'La carga excede la capacidad de este vehículo. Elige un vehículo mayor o reduce la cantidad.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.clay,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _agricolaSummaryCard({
    required PedidoAlmacenOption? origen,
    required PedidoAlmacenOption? destino,
    required PedidoTransportistaOption? driver,
    required PedidoVehiculoOption? vehiculo,
    required double totalKg,
    required double totalVolM3,
  }) {
    return Container(
      key: const ValueKey('pedido.resumen_envio'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailField(
            label: 'Desde',
            value: origen?.nombre ?? 'Sin seleccionar',
          ),
          const Divider(height: 1),
          DetailField(
            label: 'Hasta',
            value: destino?.nombre ?? 'Sin seleccionar',
          ),
          const Divider(height: 1),
          DetailField(
            label: 'Carga total',
            value: totalKg > 0
                ? '${_formatKg(totalKg)} kg · ~${totalVolM3.toStringAsFixed(2)} m³'
                : 'Sin definir',
          ),
          const Divider(height: 1),
          DetailField(
            label: 'Chofer y vehículo',
            value: driver != null && vehiculo != null
                ? '${driver.nombre} · ${vehiculo.placa}'
                : 'Sin asignar',
          ),
          const Divider(height: 1),
          DetailField(
            label: 'Costo estimado',
            value: _costoBsCtrl.text.trim().isNotEmpty
                ? 'Bs ${_costoBsCtrl.text.trim()}'
                : 'Por calcular',
          ),
        ],
      ),
    );
  }

  Widget _buildTipoSelector(List<PedidoTipo> allowed, ModuleLook look) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Tipo de pedido', color: look.tone),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final tipo in allowed)
              ChoiceChip(
                key: ValueKey('pedido.form.tipo.${tipo.value}'),
                label: Text(tipo.label),
                selected: _tipo == tipo,
                selectedColor: AppTheme.maize,
                backgroundColor: AppTheme.surface,
                side: const BorderSide(color: AppTheme.ink, width: 1.5),
                onSelected: _submitting
                    ? null
                    : (_) {
                        setState(() {
                          _tipo = tipo;
                          _submitError = null;
                        });
                        if (tipo == PedidoTipo.agricola &&
                            _agricolaForm == null &&
                            !_loadingAgricolaForm) {
                          unawaited(_loadAgricolaForm());
                        }
                      },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDistribucionBody(BuildContext context) {
    final look = AppModule.pedidos.look;
    final allowed = _allowedTipos;
    final scrollPadding = formScrollPadding(context);
    final generalError = _submitError?.message;
    final detallesError = _fieldError('detalles');
    final distData = _distFormData;
    final useSelectors = distData != null && distData.hasOptions;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (allowed.length > 1) ...[
                  _buildTipoSelector(allowed, look),
                  const SizedBox(height: 20),
                ],
                SectionTitle('Destino y entrega', color: look.tone),
                const SizedBox(height: 12),
                if (useSelectors)
                  DropdownButtonFormField<int>(
                    key: const ValueKey('pedido.destino'),
                    initialValue: _distPuntoVentaId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Punto de venta destino *',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                    items: [
                      for (final pv in distData.puntosVenta)
                        DropdownMenuItem<int>(
                          value: pv.id,
                          child: Text(
                            pv.direccion != null
                                ? '${pv.nombre} · ${pv.direccion}'
                                : pv.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (val) {
                            setState(() {
                              _distPuntoVentaId = val;
                              _destinoCtrl.text = val == null ? '' : '$val';
                            });
                            _clearError(field: 'puntoventaid');
                          },
                    validator: (val) => val == null
                        ? 'Indica el punto de venta destino.'
                        : null,
                  )
                else
                  TextFormField(
                    key: const ValueKey('pedido.destino'),
                    controller: _destinoCtrl,
                    scrollPadding: scrollPadding,
                    enabled: !_submitting,
                    keyboardType: TextInputType.number,
                    forceErrorText: _fieldError('puntoventaid'),
                    decoration: const InputDecoration(
                      labelText: 'Punto de venta destino (ID)',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) {
                        return 'Indica el punto de venta destino.';
                      }
                      if ((int.tryParse(text) ?? 0) <= 0) {
                        return 'Indica un ID de punto de venta válido.';
                      }
                      return null;
                    },
                    onChanged: (_) => _clearError(field: 'puntoventaid'),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('pedido.fecha_entrega'),
                  controller: _fechaEntregaCtrl,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  forceErrorText: _fieldError('fecha_entrega_deseada'),
                  decoration: InputDecoration(
                    labelText: 'Fecha de entrega deseada (AAAA-MM-DD)',
                    prefixIcon: const Icon(Icons.event_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Elegir fecha',
                      onPressed: _submitting ? null : _pickFechaEntrega,
                      icon: const Icon(Icons.calendar_today_rounded),
                    ),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return 'Indica la fecha de entrega deseada.';
                    }
                    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
                      return 'Usa el formato AAAA-MM-DD.';
                    }
                    return null;
                  },
                  onChanged: (_) => _clearError(field: 'fecha_entrega_deseada'),
                ),
                const SizedBox(height: 12),
                if (useSelectors && distData.almacenesMayoristas.isNotEmpty)
                  DropdownButtonFormField<int>(
                    key: const ValueKey('pedido.almacen_origen'),
                    initialValue: _distAlmacenMayoristaId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Almacén mayorista origen (opcional)',
                      prefixIcon: Icon(Icons.warehouse_outlined),
                    ),
                    items: [
                      for (final a in distData.almacenesMayoristas)
                        DropdownMenuItem<int>(
                          value: a.id,
                          child: Text(
                            a.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (val) {
                            setState(() {
                              _distAlmacenMayoristaId = val;
                              _origenAlmacenCtrl.text = val == null
                                  ? ''
                                  : '$val';
                            });
                            _clearError(field: 'almacen_mayorista_origenid');
                          },
                  )
                else
                  TextFormField(
                    key: const ValueKey('pedido.almacen_origen'),
                    controller: _origenAlmacenCtrl,
                    scrollPadding: scrollPadding,
                    enabled: !_submitting,
                    keyboardType: TextInputType.number,
                    forceErrorText: _fieldError('almacen_mayorista_origenid'),
                    decoration: const InputDecoration(
                      labelText: 'Almacén mayorista origen (ID opcional)',
                      prefixIcon: Icon(Icons.warehouse_outlined),
                    ),
                    onChanged: (_) =>
                        _clearError(field: 'almacen_mayorista_origenid'),
                  ),
                const SizedBox(height: 24),
                SectionTitle(
                  'Productos, presentaciones y cantidades',
                  color: look.tone,
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _distLines.length; i++) ...[
                  _distLineCard(i, distData, scrollPadding),
                  const SizedBox(height: 12),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey('pedido.agregar_linea'),
                    onPressed: _submitting
                        ? null
                        : () => setState(
                            () => _distLines.add(_DistDraftLineControllers()),
                          ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar producto'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('pedido.observaciones'),
                  controller: _observacionesCtrl,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                if (detallesError != null) ...[
                  const SizedBox(height: 14),
                  AppNotice(tone: AppNoticeTone.error, message: detallesError),
                ] else if (generalError != null) ...[
                  const SizedBox(height: 14),
                  AppNotice(tone: AppNoticeTone.error, message: generalError),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('pedido.guardar'),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _submitting ? 'Guardando pedido...' : 'Crear pedido',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _distLineCard(
    int index,
    PedidoDistribucionFormData? distData,
    EdgeInsets scrollPadding,
  ) {
    final line = _distLines[index];
    final useSelectors = distData != null && distData.hasOptions;
    PedidoDistribucionProductoOption? selectedProd;
    if (useSelectors && line.selectedProductoId != null) {
      for (final p in distData.productos) {
        if (p.insumoId == line.selectedProductoId) {
          selectedProd = p;
          break;
        }
      }
    }

    return Container(
      key: ValueKey('pedido.linea.$index'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Producto #${index + 1}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (_distLines.length > 1)
                IconButton(
                  tooltip: 'Quitar producto',
                  onPressed: _submitting
                      ? null
                      : () => _removeUndoable(
                          _distLines,
                          index,
                          'Producto quitado',
                          dispose: (line) => line.dispose(),
                        ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (useSelectors) ...[
            DropdownButtonFormField<int>(
              key: ValueKey('pedido.linea.$index.producto'),
              initialValue: line.selectedProductoId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Producto *'),
              items: [
                for (final p in distData.productos)
                  DropdownMenuItem<int>(
                    value: p.insumoId,
                    child: Text(
                      '${p.label} (${_formatKg(p.stockKg)} kg)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (val) {
                      setState(() {
                        line.selectedProductoId = val;
                        line.producto.text = val == null ? '' : '$val';
                        line.selectedPresentacionId = null;
                        line.presentacion.clear();
                        if (val != null) {
                          for (final p in distData.productos) {
                            if (p.insumoId == val &&
                                p.presentaciones.length == 1) {
                              line.selectedPresentacionId =
                                  p.presentaciones.first.id;
                              line.presentacion.text =
                                  '${p.presentaciones.first.id}';
                            }
                          }
                        }
                      });
                      _clearError(field: 'detalles.$index.insumoid');
                    },
              validator: (val) => val == null ? 'Indica el producto.' : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              key: ValueKey('pedido.linea.$index.presentacion'),
              initialValue: line.selectedPresentacionId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Presentación *'),
              items: [
                if (selectedProd != null)
                  for (final pres in selectedProd.presentaciones)
                    DropdownMenuItem<int>(
                      value: pres.id,
                      child: Text(
                        '${pres.nombre} (${pres.stockUnidades.toStringAsFixed(0)} ${pres.unidadEtiqueta} disp.)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: _submitting
                  ? null
                  : (val) {
                      setState(() {
                        line.selectedPresentacionId = val;
                        line.presentacion.text = val == null ? '' : '$val';
                      });
                      _clearError(
                        field: 'detalles.$index.insumo_presentacionid',
                      );
                    },
              validator: (val) =>
                  val == null ? 'Selecciona la presentación.' : null,
            ),
          ] else ...[
            TextFormField(
              key: ValueKey('pedido.linea.$index.producto'),
              controller: line.producto,
              scrollPadding: scrollPadding,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              forceErrorText: _fieldError('detalles.$index.insumoid'),
              decoration: const InputDecoration(
                labelText: 'Producto (ID de insumo)',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'Indica el producto.';
                if ((int.tryParse(text) ?? 0) <= 0) {
                  return 'Indica un ID de producto válido.';
                }
                return null;
              },
              onChanged: (_) => _clearError(field: 'detalles.$index.insumoid'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('pedido.linea.$index.presentacion'),
              controller: line.presentacion,
              scrollPadding: scrollPadding,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              forceErrorText: _fieldError(
                'detalles.$index.insumo_presentacionid',
              ),
              decoration: const InputDecoration(labelText: 'Presentación (ID)'),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'Selecciona la presentación.';
                if ((int.tryParse(text) ?? 0) <= 0) {
                  return 'Indica un ID de presentación válido.';
                }
                return null;
              },
              onChanged: (_) =>
                  _clearError(field: 'detalles.$index.insumo_presentacionid'),
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('pedido.linea.$index.cantidad'),
            controller: line.cantidad,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            forceErrorText: _fieldError('detalles.$index.cantidad'),
            decoration: const InputDecoration(
              labelText: 'Cantidad (envases)',
              suffixText: 'env.',
            ),
            validator: (value) =>
                validatePedidoQuantity(value, unitLabel: 'envases'),
            onChanged: (_) => _clearError(field: 'detalles.$index.cantidad'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('pedido.linea.$index.partida'),
            controller: line.partida,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            forceErrorText: _fieldError(
              'detalles.$index.inventario_presentacion_loteid',
            ),
            decoration: const InputDecoration(
              labelText: 'Partida (ID opcional)',
            ),
            onChanged: (_) => _clearError(
              field: 'detalles.$index.inventario_presentacion_loteid',
            ),
          ),
        ],
      ),
    );
  }
}
