<?php

namespace App\Services;

use App\Models\Actividad;
use App\Models\AlmacenMovimiento;
use App\Models\DetallePedido;
use App\Models\DetallePedidoDistribucion;
use App\Models\DetalleTrasladoPlantaMayorista;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Models\PedidoDistribucion;
use App\Models\Produccion;
use App\Models\RecepcionQrEnvio;
use App\Models\RegistroProcesoMaquinaPlanta;
use App\Models\RutaDistribucion;
use App\Models\Usuario;
use App\Support\ActividadPermisos;
use App\Support\AlmacenAcceso;
use App\Support\CertificadoAcceso;
use App\Support\LoteAcceso;
use App\Support\ProduccionPlantaAcceso;
use App\Support\PuntoVentaAccess;
use App\Support\RecorridoFiltros;
use App\Support\UsuarioRol;

/** Explicit foreign keys only. Filtering marks matches without deleting provenance context. */
final class ProductoRecorridoConsultaService
{
    public function consultar(string $tipo, int $id, Usuario $usuario, array $f): array
    {
        abort_unless(in_array($tipo, ['cosecha', 'planta'], true), 404);
        $almacenes = $usuario->can('inventario.view') ? AlmacenAcceso::idsVisibles($usuario) : [];
        $eventos = [];
        $origenesCampo = [];
        $pedidosAgricolas = [];
        $lineasAgricolas = [];
        $partidas = [];
        $emisiones = [];
        if ($tipo === 'planta') {
            $lote = ProduccionPlantaAcceso::scope(LoteProduccionPedido::query(), $usuario)->findOrFail($id);
            $base = app(ProduccionPlantaRecorridoService::class)->consultar($lote, $usuario);
            if (CertificadoAcceso::planta($usuario, $lote)) {
                $emisiones = $lote->evaluacionesFinales()->orderBy('evaluacionfinalloteid')
                    ->get()->map(fn ($e) => ['tipo' => 'planta', 'id' => (int) $e->getKey(),
                        'codigo' => $e->codigo_certificado, 'fecha' => $e->fecha_evaluacion?->toIso8601String()])->all();
            }
            $origenesCampo = array_filter(array_column($base['origenes'], 'origen_agricola'));
            foreach ($base['origenes'] as $o) {
                $eventos[] = $this->evento('origen', $o['consumo_id'], $o['recepcion']['fecha'] ?? null, $o['almacen_id'], $o, $f);
                if ($o['recepcion']) {
                    $pedidosAgricolas[] = $o['recepcion']['pedidoid'];
                    $lineasAgricolas[] = $o['recepcion']['detallepedidoid'];
                }
            }
            foreach ($base['ingresos_produccion'] as $ingreso) {
                $eventos[] = $this->evento('ingreso_produccion', $ingreso['almacenaje_id'], $ingreso['fecha'], $ingreso['almacen_id'], $ingreso, $f);
            }
            foreach ($base['ubicaciones_actuales'] as $ubicacion) {
                $eventos[] = $this->evento('ubicacion_actual', $ubicacion['partida_id'], null, $ubicacion['almacen_id'], $ubicacion, $f, true);
            }
            $partidas = array_column($base['productos_obtenidos'], 'partida_id');
            $etapas = RegistroProcesoMaquinaPlanta::where('loteproduccionpedidoid', $id);
            if (UsuarioRol::esOperarioPlanta($usuario)) {
                $etapas->where('usuarioid', $usuario->getKey());
            }
            foreach ($etapas->orderBy('registroprocesomaquinaplantaid')->get() as $r) {
                $datos = json_decode($r->variables_ingresadas ?? '{}', true) ?: [];
                $eventos[] = $this->evento('etapa_planta', (int) $r->getKey(), $r->fecha_registro?->toIso8601String(), null,
                    ['loteproduccionpedidoid' => $id, 'responsable_id' => $r->usuarioid,
                        'proceso' => $datos['proceso'] ?? null, 'maquina' => $datos['maquina'] ?? null,
                        'inicio' => $r->hora_inicio?->toIso8601String(), 'fin' => $r->hora_fin?->toIso8601String(),
                        'parametros' => $datos['parametros'] ?? [], 'observaciones' => $r->observaciones], $f);
            }
        } else {
            abort_unless($usuario->can('lotes.view'), 403);
            $lotes = Lote::query();
            LoteAcceso::aplicarScopeVisibles($lotes, $usuario);
            $cosecha = Produccion::whereIn('loteid', $lotes->select('loteid'))->with('unidadMedida')->findOrFail($id);
            $base = ['nivel' => 'cosecha', 'cosecha' => ['produccionid' => $id, 'loteid' => $cosecha->loteid,
                'fecha' => $cosecha->fechacosecha?->toDateString(), 'cantidad' => $cosecha->cantidad,
                'unidad' => $cosecha->unidadMedida?->abreviatura ?: $cosecha->unidadMedida?->nombre,
                'presentacion_cosecha' => $cosecha->presentacion_cosecha]];
            $origenesCampo[] = ['loteid' => $cosecha->loteid, 'produccionid' => $id];
            if (CertificadoAcceso::campo($usuario, $cosecha->lote)) {
                $emisiones = $cosecha->lote->certificaciones()->orderBy('certificacionid')->get()
                    ->map(fn ($e) => ['tipo' => 'campo', 'id' => (int) $e->getKey(), 'codigo' => $e->codigo_certificado,
                        'fecha' => $e->fecha_certificacion?->toIso8601String()])->all();
            }
            $eventos[] = $this->evento('cosecha', $id, $base['cosecha']['fecha'], null, $base['cosecha'], $f);
            foreach ($cosecha->almacenamientos()->whereIn('almacenid', $almacenes)->orderBy('produccionalmacenamientoid')->get() as $a) {
                $eventos[] = $this->evento('almacenamiento_agricola', (int) $a->getKey(), $a->fechaentrada?->toIso8601String(), (int) $a->almacenid,
                    ['produccionid' => $id, 'cantidad_actual' => (string) $a->getRawOriginal('cantidad'),
                        'unidadmedidaid' => $a->unidadmedidaid, 'fecha_salida' => $a->fechasalida?->toIso8601String()], $f);
            }
            $pedidosAgricolas = DetallePedido::whereHas('cosechaAlmacen', fn ($q) => $q->where('produccionid', $id))->pluck('pedidoid')->all();
            $lineasAgricolas = DetallePedido::whereHas('cosechaAlmacen', fn ($q) => $q->where('produccionid', $id))->pluck('detallepedidoid')->all();
            if ($cosecha->almacendestinoid && in_array((int) $cosecha->almacendestinoid, $almacenes, true)) {
                $eventos[] = $this->evento('destino_planificado_cosecha', $id, null, (int) $cosecha->almacendestinoid,
                    ['produccionid' => $id, 'confirmacion' => 'Destino planificado; no acredita recepción'], $f);
            }
            $derivados = ProduccionPlantaAcceso::scope(LoteProduccionPedido::query(), $usuario)
                ->whereHas('materiasPrimas.materiaPrimaLote.detallePedido.cosechaAlmacen', fn ($q) => $q->where('produccionid', $id));
            foreach ($derivados->orderBy('loteproduccionpedidoid')->get() as $derivado) {
                $datos = app(ProduccionPlantaRecorridoService::class)->consultar($derivado, $usuario);
                $vinculos = array_values(array_filter($datos['origenes'], fn ($o) => ($o['origen_agricola']['produccionid'] ?? null) === $id));
                if ($vinculos !== []) {
                    $eventos[] = $this->evento('produccion_planta_derivada', (int) $derivado->getKey(), $derivado->fecha_creacion?->toDateString(), null,
                        ['loteproduccionpedidoid' => (int) $derivado->getKey(), 'codigo' => $derivado->codigo_lote,
                            'consumos_vinculados' => $vinculos, 'productos_obtenidos' => $datos['productos_obtenidos'],
                            'ingresos_produccion' => $datos['ingresos_produccion']], $f);
                }
            }
        }
        // Fetch each agricultural lot once, only for authorized agricultural modules.
        if ($usuario->can('lotes.view')) {
            $campoIds = array_unique(array_column($origenesCampo, 'loteid'));
            $query = Actividad::whereIn('loteid', $campoIds)->with('tipoActividad');
            ActividadPermisos::aplicarScopeVisibles($query, $usuario);
            foreach ($query->orderBy('actividadid')->get() as $a) {
                $eventos[] = $this->evento('actividad_agricola', (int) $a->getKey(), $a->fechafin?->toIso8601String(), null,
                    ['loteid' => $a->loteid, 'descripcion' => $a->tipoActividad?->nombre,
                        'responsable_id' => $a->usuarioid_ejecutor ?? $a->usuarioid,
                        'estado' => $a->fechafin ? 'completada' : 'pendiente', 'fecha_planificada' => $a->fecha_planificada?->toDateString()], $f);
            }
        }
        if ($usuario->can('inventario.view') && $usuario->can('almacen.movimientos.view') && $tipo === 'planta') {
            foreach (AlmacenMovimiento::where('loteproduccionpedidoid', $id)->whereIn('almacenid', $almacenes)
                ->with('unidadMedida')->orderBy('almacen_movimientoid')->get() as $m) {
                $eventos[] = $this->evento('movimiento', (int) $m->getKey(), $m->fecha?->toDateString(), (int) $m->almacenid,
                    ['loteproduccionpedidoid' => $id, 'insumoid' => $m->insumoid, 'materiaprimaloteid' => $m->materiaprimaloteid,
                        'inventario_presentacion_loteid' => $m->inventario_presentacion_loteid,
                        'cantidad' => $m->cantidad, 'unidad' => $m->unidadMedida?->abreviatura,
                        'cantidad_unidades' => $m->getRawOriginal('cantidad_unidades')], $f);
            }
        }
        $consultaEnvios = app(EnvioMovilConsultaService::class);
        if ($tipo === 'planta' && $usuario->can('inventario.view') && $consultaEnvios->permiso('traslado', $usuario)) {
            $rutas = $consultaEnvios->consulta('traslado', $usuario)->select('rutadistribucionid');
            foreach (DetalleTrasladoPlantaMayorista::where('loteproduccionpedidoid', $id)->whereIn('rutadistribucionid', $rutas)
                ->whereHas('ruta', fn ($q) => $q->whereIn('almacen_planta_origenid', $almacenes))
                ->with('ruta')->orderBy('detalletrasladoid')->get() as $d) {
                $ruta = $d->ruta;
                // A permitted origin does not authorize identities of unrelated destination warehouses.
                $destino = in_array((int) $ruta->almacen_mayorista_destinoid, $almacenes, true) ? (int) $ruta->almacen_mayorista_destinoid : null;
                $origen = (int) $ruta->almacen_planta_origenid;
                $almacenOperacion = $destino !== null && (int) ($f['almacenid'] ?? 0) === $destino ? $destino : $origen;
                $eventos[] = $this->evento('traslado', (int) $d->getKey(), $ruta->fecha_salida?->toIso8601String(), $almacenOperacion,
                    ['loteproduccionpedidoid' => $id, 'rutadistribucionid' => (int) $ruta->getKey(), 'estado' => $ruta->estado,
                        'almacen_origenid' => $origen, 'almacen_destinoid' => $destino,
                        'producto' => $d->producto_nombre, 'presentacion' => $d->presentacion_nombre,
                        'cantidad_kg' => $d->getRawOriginal('cantidad'), 'cantidad_unidades' => $d->getRawOriginal('cantidad_unidades'),
                        'cantidad_recibida' => $d->getRawOriginal('cantidad_recibida'),
                        'destino_tipo' => $ruta->llegada_confirmada_at ? 'llegada registrada; consultar recepción' : 'planificado'], $f);
                $eventos = array_merge($eventos, $this->recepciones($ruta, $usuario, [(int) $d->getKey()], $destino, $f));
            }
        }
        if ($pedidosAgricolas && $consultaEnvios->permiso('agricola', $usuario)) {
            foreach ($consultaEnvios->consulta('agricola', $usuario)->whereIn('pedidoid', array_unique($pedidosAgricolas))->orderBy('envioasignacionmultipleid')->get() as $e) {
                // Do not serialize the other order lines: the link identifies only this operation.
                $eventos[] = $this->evento('envio_agricola', (int) $e->getKey(), $e->fecha_salida?->toIso8601String(), null,
                    ['pedidoid' => $e->pedidoid, 'estado' => $e->estado, 'fecha_recepcion' => $e->fecha_recepcion_planta?->toIso8601String(),
                        'destino' => $e->pedido?->nombre_planta, 'destino_tipo' => $e->fecha_recepcion_planta ? 'recepción registrada' : 'planificado'], $f);
                $eventos = array_merge($eventos, $this->recepciones($e, $usuario, $lineasAgricolas, null, $f));
            }
        }
        if ($partidas && $usuario->can('pedidos_distribucion.view')) {
            $pedidos = PuntoVentaAccess::scopePedidosDelUsuario(PedidoDistribucion::query(), $usuario)->select('pedidodistribucionid');
            foreach (DetallePedidoDistribucion::whereIn('inventario_presentacion_loteid', $partidas)->whereIn('pedidodistribucionid', $pedidos)
                ->with('pedido')->orderBy('detallepedidodistribucionid')->get() as $d) {
                $eventos[] = $this->evento('pedido_distribucion', (int) $d->getKey(), $d->pedido->fechapedido?->toIso8601String(),
                    $d->almacen_mayorista_origenid ?? $d->pedido->almacen_mayorista_origenid,
                    ['pedidodistribucionid' => $d->pedidodistribucionid, 'inventario_presentacion_loteid' => $d->inventario_presentacion_loteid,
                        'numero_solicitud' => $d->pedido->numero_solicitud, 'estado' => $d->pedido->estado,
                        'cantidad' => (string) $d->getRawOriginal('cantidad'), 'unidad' => $d->datos_solicitud['unidad'] ?? null,
                        'presentacion' => $d->datos_solicitud['presentacion'] ?? null,
                        'fecha_recepcion' => $d->pedido->fecha_recepcion?->toIso8601String(), 'rutadistribucionid' => $d->pedido->rutadistribucionid], $f);
                if ($d->pedido->rutadistribucionid && $consultaEnvios->permiso('distribucion', $usuario)) {
                    $ruta = $consultaEnvios->consulta('distribucion', $usuario)->find($d->pedido->rutadistribucionid);
                    if ($ruta) {
                        $eventos = array_merge($eventos, $this->recepciones($ruta, $usuario, [(int) $d->getKey()], null, $f));
                    }
                }
            }
        }

        return ['entidad' => ['tipo' => $tipo, 'id' => $id], 'antecedentes' => $base, 'elementos' => $eventos, 'emisiones_historicas' => $emisiones,
            'coincidencias' => count(array_filter($eventos, fn ($e) => $e['coincide_filtros'])),
            'criterio' => 'Los antecedentes fuera del periodo se conservan como contexto. Un dato ausente indica información no registrada o no disponible para esta cuenta. Las ubicaciones muestran el saldo actual; el filtro de fecha no aplica a esos saldos.'];
    }

    /** Only persisted, authorized receipts containing a line of this particular batch. */
    private function recepciones(EnvioAsignacionMultiple|RutaDistribucion $envio, Usuario $usuario, array $lineas, ?int $almacen, array $f): array
    {
        $resultado = [];
        $tipo = app(EnvioMovilConsultaService::class)->tipo($envio);
        foreach (app(EntregaWebPresentacionService::class)->comprobantes($envio, $usuario) as $comprobante) {
            $qr = RecepcionQrEnvio::findOrFail($comprobante['id']);
            foreach ($qr->datos_recepcion['lineas'] ?? [] as $linea) {
                if (! in_array((int) ($linea['id'] ?? 0), array_map('intval', $lineas), true)) {
                    continue;
                }
                $resultado[] = $this->evento('recepcion_'.$tipo, (int) $linea['id'], $qr->utilizado_en->toIso8601String(), $almacen,
                    ['recepcion_id' => (int) $qr->getKey(), 'envio_id' => (int) $envio->getKey(), 'pedido_id' => $linea['pedido_id'] ?? null,
                        'producto' => $linea['producto'] ?? null, 'presentacion' => $linea['presentacion'] ?? null,
                        'cantidad_recibida' => $linea['cantidad_recibida'] ?? null, 'unidad_recepcion' => $linea['unidad'] ?? null,
                        'destino_tipo' => 'Recepción confirmada', 'comprobante_url' => $comprobante['url']], $f);
            }
        }

        return $resultado;
    }

    private function evento(string $tipo, int $id, ?string $fecha, ?int $almacen, array $datos, array $f, bool $actual = false): array
    {
        $coincide = RecorridoFiltros::coincide($fecha, $almacen, $actual ? array_diff_key($f, ['desde' => 1, 'hasta' => 1]) : $f, $almacen !== null);

        return ['tipo' => $tipo, 'id' => $id, 'fecha' => $fecha, 'almacenid' => $almacen,
            'fecha_filtro_aplica' => ! $actual, 'almacen_filtro_aplica' => $almacen !== null,
            'coincide_filtros' => $coincide, 'datos' => $datos];
    }
}
