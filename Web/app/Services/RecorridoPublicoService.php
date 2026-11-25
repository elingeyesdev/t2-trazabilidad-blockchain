<?php

namespace App\Services;

use App\Models\Actividad;
use App\Models\AlmacenMovimiento;
use App\Models\DetallePedido;
use App\Models\DetallePedidoDistribucion;
use App\Models\DetalleTrasladoPlantaMayorista;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Insumo;
use App\Models\InventarioPresentacionLote;
use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Models\MateriaPrimaLote;
use App\Models\PedidoDistribucion;
use App\Models\Produccion;
use App\Models\RecepcionQrEnvio;
use App\Support\InventarioDecimal;
use Illuminate\Database\Eloquent\Collection as ModelCollection;
use Illuminate\Support\Collection;

/** Public, read-only projection. Neither legacy inference nor synchronization is invoked. */
final class RecorridoPublicoService
{
    public function desdeLote(Lote $lote): array
    {
        $lote->loadMissing('cultivo');
        $procesos = LoteProduccionPedido::query()
            ->whereHas('materiasPrimas', fn ($q) => $q->whereHas('materiaPrimaLote',
                fn ($mp) => $mp->whereColumn('materia_prima_lote.insumoid', 'lote_produccion_materia_prima.insumoid')
                    ->whereHas('detallePedido.cosechaAlmacen.produccion',
                        fn ($c) => $c->where('loteid', $lote->getKey()))))->get();

        // Follow explicit industrial consumption links, including multiple descendants.
        $vistos = new ModelCollection;
        $pendientes = $procesos;
        while ($pendientes->isNotEmpty()) {
            $nuevos = $pendientes->reject(fn ($p) => $vistos->has($p->getKey()));
            if ($nuevos->isEmpty()) {
                break;
            }
            $vistos = $vistos->union($nuevos->keyBy(fn ($p) => $p->getKey()));
            $pendientes = LoteProduccionPedido::query()
                ->whereHas('materiasPrimas', fn ($q) => $q->whereHas('presentacionLote',
                    fn ($p) => $p->whereColumn('inventario_presentacion_lote.insumoid', 'lote_produccion_materia_prima.insumoid')
                        ->whereIn('loteproduccionpedidoid', $nuevos->modelKeys())))->get();
        }

        return $this->construir($vistos->values(), new ModelCollection([$lote]), null);
    }

    public function desdePdv(Insumo $insumo): array
    {
        $partidas = InventarioPresentacionLote::query()->where('insumoid', $insumo->getKey())
            ->where('almacenid', $insumo->almacenid)->with('presentacion')->get();
        $procesos = LoteProduccionPedido::query()
            ->whereKey($partidas->pluck('loteproduccionpedidoid')->filter()->unique())->get();

        return $this->construir($procesos, new ModelCollection, $insumo, $partidas);
    }

    private function construir(Collection $procesos, Collection $campos, ?Insumo $pdv, ?Collection $partidasPdv = null): array
    {
        $etapas = collect(['agricola', 'planta', 'mayorista', 'distribucion', 'pdv'])
            ->mapWithKeys(fn ($tipo) => [$tipo => []])->all();
        $rutas = [];
        $productoCampo = $campos->first();
        $cosechas = new ModelCollection;
        $detallesAgricolas = new ModelCollection;
        $todos = new ModelCollection;
        $pendientes = $procesos;
        $relaciones = ['materiasPrimas.insumo', 'materiasPrimas.movimientoConsumo.unidadMedida',
            'materiasPrimas.materiaPrimaLote.detallePedido.cosechaAlmacen.produccion.lote.cultivo',
            'materiasPrimas.presentacionLote', 'registrosProceso.procesoMaquina.proceso',
            'almacenajes'];

        // A product may consume other industrial batches. A visited set handles cycles safely.
        while ($pendientes->isNotEmpty()) {
            $nuevos = $pendientes->reject(fn ($p) => $todos->has($p->getKey()));
            if ($nuevos->isEmpty()) {
                break;
            }
            $nuevos->loadMissing($relaciones);
            $todos = $todos->union($nuevos->keyBy(fn ($p) => $p->getKey()));
            $antecesores = $nuevos->flatMap(fn ($p) => $p->materiasPrimas
                ->filter(fn ($m) => ! $m->presentacionLote || (int) $m->presentacionLote->insumoid === (int) $m->insumoid)
                ->pluck('presentacionLote.loteproduccionpedidoid'))->filter()->unique();
            $pendientes = LoteProduccionPedido::whereKey($antecesores)->get();
        }

        foreach ($todos->sortKeys() as $proceso) {
            $codigo = $this->codigo($proceso->codigo_lote);
            $this->agregar($etapas['planta'], 'produccion:'.$proceso->getKey(), [
                'tipo' => 'produccion_registrada', 'fecha' => $this->fecha($proceso->fecha_creacion),
                'fecha_tipo' => 'creacion', 'codigo_lote' => $codigo,
            ]);
            foreach ($proceso->materiasPrimas as $materia) {
                $partida = $materia->materiaPrimaLote;
                $industrial = $materia->presentacionLote;
                // A mismatched catalog/partida is not evidence for this consumption.
                if (($partida && (int) $partida->insumoid !== (int) $materia->insumoid)
                    || ($industrial && (int) $industrial->insumoid !== (int) $materia->insumoid)) {
                    continue;
                }
                $detalle = $partida?->detallePedido;
                $cosecha = $detalle?->cosechaAlmacen?->produccion;
                if ($cosecha) {
                    $cosechas->put($cosecha->getKey(), $cosecha);
                    if ($cosecha->lote) {
                        $campos->put($cosecha->lote->getKey(), $cosecha->lote);
                    }
                    $detallesAgricolas->put($detalle->getKey(), $detalle);
                }
                $movimiento = $materia->movimientoConsumo;
                $valido = $movimiento && (int) $movimiento->loteproduccionpedidoid === (int) $proceso->getKey()
                    && (int) $movimiento->insumoid === (int) $materia->insumoid
                    && (int) $movimiento->materiaprimaloteid === (int) $materia->materiaprimaloteid
                    && (int) $movimiento->inventario_presentacion_loteid === (int) $materia->inventario_presentacion_loteid;
                $this->agregar($etapas['planta'], 'consumo:'.$materia->getKey(), [
                    'tipo' => 'consumo_registrado', 'fecha' => $valido ? $this->fecha($movimiento->fecha, true) : null,
                    'fecha_tipo' => 'consumo', 'codigo_lote' => $codigo,
                    'codigo_origen_agricola' => $this->codigo($cosecha?->lote?->codigo_trazabilidad),
                    'codigo_origen_industrial' => $this->codigo($todos->get($industrial?->loteproduccionpedidoid)?->codigo_lote),
                    'referencia_cosecha' => $cosecha ? 'cosecha:'.$cosecha->getKey() : null,
                    'referencia_partida_origen' => $industrial ? 'partida:'.$industrial->getKey()
                        : ($partida ? 'materia_prima:'.$partida->getKey() : null),
                    'cantidad_consumida' => $this->decimal($materia->getRawOriginal('cantidad_usada')),
                    'cantidad_unidades_consumidas' => $this->decimal($materia->getRawOriginal('cantidad_unidades_consumidas')),
                    'unidad' => $valido ? ($movimiento->unidadMedida?->abreviatura ?: $movimiento->unidadMedida?->nombre) : null,
                ]);
            }
            foreach ($proceso->registrosProceso as $registro) {
                $this->agregar($etapas['planta'], 'etapa_planta:'.$registro->getKey(), [
                    'tipo' => 'etapa_registrada', 'codigo_lote' => $codigo,
                    'proceso' => $registro->procesoMaquina?->proceso?->nombre,
                    'fecha' => $this->fecha($registro->fecha_registro), 'fecha_tipo' => 'registro_cierre',
                    'fecha_inicio' => $this->fecha($registro->hora_inicio),
                    'fecha_fin' => $this->fecha($registro->hora_fin),
                ]);
            }
            foreach ($proceso->almacenajes as $ingreso) {
                if ($pdv && ! ($partidasPdv?->contains(fn ($p) => (int) $p->getKey() === (int) $ingreso->inventario_presentacion_loteid))) {
                    continue;
                }
                // Only immutable historical intake quantities; never infer output from current stock.
                $datos = $ingreso->datos_ingreso;
                $this->agregar($etapas['planta'], 'ingreso_produccion:'.$ingreso->getKey(), [
                    'tipo' => 'ingreso_produccion', 'codigo_lote' => $codigo,
                    'fecha' => $this->fecha($datos['fecha'] ?? $ingreso->fecha_almacenaje),
                    'fecha_tipo' => 'ingreso',
                    'referencia_partida' => $ingreso->inventario_presentacion_loteid ? 'partida:'.$ingreso->inventario_presentacion_loteid : null,
                    'producto' => $datos['producto'] ?? null, 'presentacion' => $datos['presentacion'] ?? null,
                    'cantidad' => $this->decimal($datos['cantidad_unidades'] ?? null),
                    'cantidad_kg' => $this->decimal($datos['cantidad_kg'] ?? null), 'unidad' => $datos['unidad'] ?? null,
                ]);
            }
        }

        $campos = $campos->unique(fn ($l) => $l->getKey())->sortBy(fn ($l) => $l->getKey())->values();
        $campos->loadMissing('cultivo');
        if ($pdv === null) {
            // Co-origins of a mixed industrial batch do not bring their other harvests.
            $cosechas = $cosechas->union(Produccion::where('loteid', $productoCampo->getKey())
                ->get()->keyBy(fn ($c) => $c->getKey()));
        }
        $cosechas->loadMissing('unidadMedida', 'lote');
        foreach ($campos as $campo) {
            $this->agregar($etapas['agricola'], 'lote:'.$campo->getKey(), [
                'tipo' => 'lote_registrado', 'fecha' => $this->fecha($campo->fechacreacion),
                'fecha_tipo' => 'registro', 'codigo_lote' => $this->codigo($campo->codigo_trazabilidad),
                'cultivo' => $campo->cultivo?->nombre,
                'fecha_siembra' => $this->fecha($campo->fechasiembra, true),
            ]);
        }
        $actividades = Actividad::whereIn('loteid', $campos->modelKeys())->with('tipoActividad')->get();
        foreach ($actividades as $actividad) {
            $campo = $campos->first(fn ($c) => (int) $c->getKey() === (int) $actividad->loteid);
            $this->agregar($etapas['agricola'], 'actividad:'.$actividad->getKey(), [
                'tipo' => 'actividad_lote_origen', 'codigo_lote' => $this->codigo($campo?->codigo_trazabilidad),
                'actividad' => $actividad->tipoActividad?->nombre,
                'estado' => $actividad->fechafin ? 'completada' : 'pendiente',
                'fecha' => $this->fecha($actividad->fechafin), 'fecha_tipo' => 'cierre',
                'fecha_programada' => $this->fecha($actividad->fecha_planificada, true),
                'fecha_inicio' => $this->fecha($actividad->fechainicio),
            ]);
        }
        foreach ($cosechas as $cosecha) {
            $presentacion = $cosecha->presentacion_cosecha ?? [];
            $this->agregar($etapas['agricola'], 'cosecha:'.$cosecha->getKey(), [
                'tipo' => 'cosecha', 'fecha' => $this->fecha($cosecha->fechacosecha, true), 'fecha_tipo' => 'cosecha',
                'codigo_lote' => $this->codigo($cosecha->lote?->codigo_trazabilidad),
                'cantidad' => $this->decimal($cosecha->getRawOriginal('cantidad')),
                'cantidad_base' => $this->decimal($cosecha->getRawOriginal('cantidad_base')),
                'unidad' => $cosecha->unidadMedida?->abreviatura ?: $cosecha->unidadMedida?->nombre,
                'presentacion' => $presentacion['nombre'] ?? null,
            ]);
        }
        if ($pdv === null) {
            $detallesAgricolas = DetallePedido::whereHas('cosechaAlmacen',
                fn ($q) => $q->whereIn('produccionid', $cosechas->modelKeys()))->get()->keyBy(fn ($d) => $d->getKey());
        }
        $this->agricolaLogistica($detallesAgricolas, $etapas, $rutas);

        // In PDV queries no sibling catalog products, transfers or other recipients are inferred.
        $partidas = $pdv ? ($partidasPdv ?? new ModelCollection) : InventarioPresentacionLote::query()
            ->whereIn('loteproduccionpedidoid', $todos->modelKeys())->with('presentacion')->get();
        $this->distribucion($partidas, $pdv, $etapas, $rutas);
        if ($pdv === null) {
            $this->traslados($todos, $etapas, $rutas);
        }
        if ($pdv) {
            foreach ($partidas as $partida) {
                $this->agregar($etapas['pdv'], 'partida:'.$partida->getKey(), [
                    'tipo' => 'partida_registrada', 'fecha' => $this->fecha($partida->created_at), 'fecha_tipo' => 'registro',
                    'codigo_producto' => $this->codigo($pdv->codigo_trazabilidad),
                    'codigo_lote' => $this->codigo($todos->get($partida->loteproduccionpedidoid)?->codigo_lote),
                    'presentacion' => $partida->presentacion?->nombre,
                ]);
            }
            foreach (AlmacenMovimiento::where('insumoid', $pdv->getKey())->where('almacenid', $pdv->almacenid)
                ->whereIn('inventario_presentacion_loteid', $partidas->modelKeys())->with('unidadMedida')->get() as $mov) {
                $this->agregar($etapas['pdv'], 'movimiento_pdv:'.$mov->getKey(), [
                    'tipo' => 'movimiento_registrado', 'fecha' => $this->fecha($mov->fecha, true), 'fecha_tipo' => 'movimiento',
                    'referencia_partida' => 'partida:'.$mov->inventario_presentacion_loteid,
                    'cantidad' => $this->decimal($mov->getRawOriginal('cantidad')),
                    'cantidad_unidades' => $this->decimal($mov->getRawOriginal('cantidad_unidades')),
                    'unidad' => $mov->unidadMedida?->abreviatura ?: $mov->unidadMedida?->nombre,
                ]);
            }
        }

        return [
            'producto' => ['codigo' => $this->codigo($pdv?->codigo_trazabilidad ?? $productoCampo?->codigo_trazabilidad),
                'nombre' => $pdv?->nombre ?? $productoCampo?->nombre,
                'cultivo' => $pdv ? null : $productoCampo?->cultivo?->nombre],
            'origenes' => $campos->map(fn ($c) => ['tipo' => 'lote_agricola',
                'codigo' => $this->codigo($c->codigo_trazabilidad), 'nombre' => $c->nombre])->all(),
            'etapas' => collect($etapas)->map(fn ($eventos, $tipo) => ['tipo' => $tipo,
                'estado' => $eventos === [] ? 'sin_informacion_registrada' : 'con_registros',
                'eventos' => collect($eventos)->sortBy(fn ($e) => [
                    $e['fecha'] === null ? PHP_INT_MAX : \Carbon\Carbon::parse($e['fecha'])->getTimestamp(),
                    $e['referencia'],
                ])->values()->all(),
            ])->values()->all(),
            'rutas' => collect($rutas)->sortBy('referencia')->values()->all(),
            'evidencias' => [], '_lotes_campo' => $campos, '_lotes_planta' => $todos->values(),
            '_actividades_publicables' => $actividades,
        ];
    }

    private function agricolaLogistica(Collection $detalles, array &$etapas, array &$rutas): void
    {
        $materias = MateriaPrimaLote::whereIn('detallepedidoid', $detalles->modelKeys())
            ->get()->keyBy(fn ($m) => $m->getKey());
        foreach (EnvioAsignacionMultiple::whereIn('pedidoid', $detalles->pluck('pedidoid')->unique())->get() as $envio) {
            $referencia = 'envio_agricola:'.$envio->getKey();
            $rutas[$referencia] = $this->ruta($referencia, 'agricola', $envio, 'campo', 'planta', $envio->fecha_recepcion_planta);
            foreach ($detalles->where('pedidoid', $envio->pedidoid) as $detalle) {
                $linea = collect($envio->recepcion_planta_datos['lineas'] ?? [])
                    ->first(fn ($l) => (int) ($l['detallepedidoid'] ?? 0) === (int) $detalle->getKey()
                        && (int) $materias->get($l['materiaprimaloteid'] ?? 0)?->detallepedidoid === (int) $detalle->getKey());
                $recibida = $linea !== null && $envio->fecha_recepcion_planta !== null;
                $this->agregar($etapas['planta'], 'recepcion_agricola:'.$detalle->getKey(), [
                    'tipo' => $recibida ? 'recepcion_registrada' : 'envio_registrado',
                    'fecha' => $this->fecha($recibida ? $envio->fecha_recepcion_planta : $envio->fecha_asignacion),
                    'fecha_tipo' => $recibida ? 'recepcion' : 'asignacion',
                    'referencia_envio' => $referencia,
                    'cantidad_recibida' => $this->decimal($linea['cantidad_recibida'] ?? null),
                    'unidad' => $linea['unidad'] ?? null,
                ]);
            }
        }
    }

    private function traslados(Collection $procesos, array &$etapas, array &$rutas): void
    {
        $detalles = DetalleTrasladoPlantaMayorista::whereIn('loteproduccionpedidoid', $procesos->modelKeys())
            ->with('ruta')->get();
        $recepciones = RecepcionQrEnvio::whereIn('rutadistribucionid', $detalles->pluck('rutadistribucionid')->unique())
            ->whereNotNull('utilizado_en')->get()->groupBy('rutadistribucionid');
        foreach ($detalles as $detalle) {
            if (! $detalle->ruta) {
                continue;
            }
            $referencia = 'traslado:'.$detalle->ruta->getKey();
            $recepcion = ($recepciones->get($detalle->rutadistribucionid) ?? collect())->first(fn ($qr) => collect($qr->datos_recepcion['lineas'] ?? [])->contains(fn ($linea) => (int) ($linea['id'] ?? 0) === (int) $detalle->getKey()));
            $lineaRecepcion = collect($recepcion?->datos_recepcion['lineas'] ?? [])
                ->first(fn ($linea) => (int) ($linea['id'] ?? 0) === (int) $detalle->getKey());
            $rutas[$referencia] = $this->ruta($referencia, 'traslado', $detalle->ruta, 'planta', 'mayorista', $recepcion?->utilizado_en);
            $this->agregar($etapas['mayorista'], 'traslado_linea:'.$detalle->getKey(), [
                'tipo' => 'traslado_registrado', 'fecha' => $this->fecha($detalle->ruta->fecha_salida), 'fecha_tipo' => 'salida',
                'referencia_envio' => $referencia, 'codigo_lote' => $this->codigo($procesos->get($detalle->loteproduccionpedidoid)?->codigo_lote),
                'producto' => $detalle->producto_nombre, 'presentacion' => $detalle->presentacion_nombre,
                'cantidad_kg' => $this->decimal($detalle->getRawOriginal('cantidad')),
                'cantidad_unidades' => $this->decimal($detalle->getRawOriginal('cantidad_unidades')),
                'cantidad_recibida' => $this->decimal($detalle->getRawOriginal('cantidad_recibida')),
                'unidad_recepcion' => $lineaRecepcion['unidad'] ?? null,
                'fecha_recepcion' => $this->fecha($recepcion?->utilizado_en),
            ]);
        }
    }

    private function distribucion(Collection $partidas, ?Insumo $pdv, array &$etapas, array &$rutas): void
    {
        if ($pdv) {
            $movimientos = AlmacenMovimiento::where('insumoid', $pdv->getKey())->where('almacenid', $pdv->almacenid)
                ->whereIn('inventario_presentacion_loteid', $partidas->modelKeys())
                ->get();
            $ids = $movimientos->pluck('detallepedidodistribucionid')->filter()->all();
            $ids = array_values(array_unique(array_merge($ids, $this->lineasPdvVerificadas($movimientos, $partidas, $pdv))));
            $consulta = DetallePedidoDistribucion::whereKey($ids)
                ->whereHas('pedido.puntoVenta', fn ($q) => $q->where('almacenid', $pdv->almacenid));
        } else {
            $consulta = DetallePedidoDistribucion::whereIn('inventario_presentacion_loteid', $partidas->modelKeys());
        }
        foreach ($consulta->with('pedido.rutaDistribucion')->get() as $detalle) {
            $pedido = $detalle->pedido;
            if (! $pedido) {
                continue;
            }
            $ruta = $pedido->rutaDistribucion;
            $referenciaRuta = $ruta ? 'distribucion:'.$ruta->getKey() : null;
            $this->agregar($etapas['distribucion'], 'pedido_distribucion_linea:'.$detalle->getKey(), [
                'tipo' => 'pedido_distribucion', 'fecha' => $this->fecha($pedido->fechapedido), 'fecha_tipo' => 'solicitud',
                'codigo_pedido' => $this->codigo($pedido->numero_solicitud), 'estado' => $pedido->estado,
                'referencia_envio' => $referenciaRuta,
                'referencia_partida' => $detalle->inventario_presentacion_loteid ? 'partida:'.$detalle->inventario_presentacion_loteid : null,
                'cantidad' => $this->decimal($detalle->getRawOriginal('cantidad')),
                'unidad' => $detalle->datos_solicitud['unidad'] ?? null,
                'presentacion' => $detalle->datos_solicitud['presentacion'] ?? null,
                'cantidad_kg' => $this->decimal($detalle->datos_solicitud['cantidad_kg'] ?? null),
                'fecha_programada' => $this->fecha($pedido->fecha_entrega_deseada, true),
                'fecha_envio' => $this->fecha($pedido->fecha_envio), 'fecha_recepcion' => $this->fecha($pedido->fecha_recepcion),
            ]);
            if ($ruta) {
                // A route-level arrival never proves receipt by this particular recipient.
                $rutas[$referenciaRuta.':'.$pedido->getKey()] = $this->ruta(
                    $referenciaRuta.':pedido:'.$pedido->getKey(), 'distribucion', $ruta, 'mayorista', 'pdv', $pedido->fecha_recepcion);
            }
        }
    }

    /**
     * Current receipts persist the exact order number and destination inventory batch on
     * their movement. The source owns the unique detail FK, so reconstruct that business
     * reference only with an unambiguous, matching, completed recipient receipt.
     * No names, descriptions, arrival dates, or current catalog conversion factors are used.
     */
    private function lineasPdvVerificadas(Collection $movimientos, Collection $partidas, Insumo $pdv): array
    {
        $pedidos = PedidoDistribucion::whereIn('numero_solicitud', $movimientos->pluck('referencia')->filter()->unique())
            ->whereHas('puntoVenta', fn ($q) => $q->where('almacenid', $pdv->almacenid))
            ->with(['puntoVenta', 'detalles.inventarioPresentacionLote'])->get();
        $porNumero = $pedidos->groupBy('numero_solicitud');
        $qrs = RecepcionQrEnvio::whereIn('rutadistribucionid', $pedidos->pluck('rutadistribucionid')->filter()->unique())
            ->whereNotNull('utilizado_en')->get()->groupBy('rutadistribucionid');
        $origenes = $pedidos->flatMap(fn ($p) => $p->detalles->pluck('inventarioPresentacionLote'))->filter();
        $partidasFuente = InventarioPresentacionLote::whereIn('loteproduccionpedidoid', $origenes->pluck('loteproduccionpedidoid')->filter()->unique())
            ->whereIn('almacenid', $origenes->pluck('almacenid')->filter()->unique())->get()
            ->groupBy(fn ($p) => $p->loteproduccionpedidoid.':'.$p->almacenid);
        $destinos = $partidas->keyBy(fn ($p) => $p->getKey());
        $resultado = [];
        foreach ($movimientos as $movimiento) {
            $coincidentes = $porNumero->get($movimiento->referencia) ?? collect();
            if ($coincidentes->count() !== 1) {
                continue;
            }
            $pedido = $coincidentes->first();
            $destino = $destinos->get($movimiento->inventario_presentacion_loteid);
            if (! $destino?->loteproduccionpedidoid || ! $pedido->fecha_recepcion || ! $pedido->rutadistribucionid) {
                continue;
            }
            $candidatos = [];
            foreach ($pedido->detalles as $detalle) {
                $origen = $detalle->inventarioPresentacionLote;
                $datos = $detalle->datos_solicitud ?? [];
                if (! $origen || (int) $origen->loteproduccionpedidoid !== (int) $destino->loteproduccionpedidoid
                    || $this->decimal($detalle->getRawOriginal('cantidad')) !== $this->decimal($movimiento->getRawOriginal('cantidad_unidades'))
                    || ! isset($datos['cantidad_kg'])
                    || $this->decimal($datos['cantidad_kg']) !== $this->decimal($movimiento->getRawOriginal('cantidad'))) {
                    continue;
                }
                $referenciaOrigen = trim((string) $origen->referencia_lote);
                $referenciaDestino = trim((string) $destino->referencia_lote);
                if ($referenciaOrigen === '' || $referenciaDestino === '' || $referenciaOrigen !== $referenciaDestino) {
                    continue;
                }
                $posibles = $partidasFuente->get($origen->loteproduccionpedidoid.':'.$origen->almacenid) ?? collect();
                $posibles = $posibles->filter(fn ($p) => trim((string) $p->referencia_lote) === $referenciaOrigen);
                // A process can produce several products or batches. A common process ID,
                // catalog product, or equal quantity alone cannot identify the destination batch.
                if ($posibles->count() !== 1 || (int) $posibles->first()->getKey() !== (int) $origen->getKey()) {
                    continue;
                }
                $pruebas = 0;
                foreach ($qrs->get($pedido->rutadistribucionid) ?? [] as $qr) {
                    $snapshot = $qr->datos_recepcion ?? [];
                    if (($snapshot['envio']['tipo'] ?? null) !== 'distribucion'
                        || (int) ($snapshot['envio']['id'] ?? 0) !== (int) $pedido->rutadistribucionid
                        || (int) $qr->destinatario_usuarioid !== (int) $pedido->puntoVenta->usuarioid) {
                        continue;
                    }
                    foreach ($snapshot['lineas'] ?? [] as $linea) {
                        if ((int) ($linea['id'] ?? 0) === (int) $detalle->getKey()
                            && (int) ($linea['pedido_id'] ?? 0) === (int) $pedido->getKey()
                            && $this->decimal($linea['cantidad_enviada'] ?? null) === $this->decimal($detalle->getRawOriginal('cantidad'))
                            && $this->decimal($linea['cantidad_recibida'] ?? null) === $this->decimal($movimiento->getRawOriginal('cantidad_unidades'))
                            && ($linea['unidad'] ?? null) === ($datos['unidad'] ?? null)) {
                            $pruebas++;
                        }
                    }
                }
                if ($pruebas === 1) {
                    $candidatos[] = (int) $detalle->getKey();
                }
            }
            if (count($candidatos) === 1) {
                $resultado[] = $candidatos[0];
            }
        }

        return array_values(array_unique($resultado));
    }

    private function ruta(string $referencia, string $tipo, $ruta, string $origen, string $destino, $recepcion = null): array
    {
        return ['referencia' => $referencia, 'tipo' => $tipo, 'codigo' => $this->codigo($ruta->codigo ?? $ruta->externo_envio_id),
            'estado' => $ruta->estado, 'origen' => ['tipo' => $origen], 'destino' => ['tipo' => $destino],
            'fecha_salida' => $this->fecha($ruta->fecha_salida),
            'fecha_salida_tipo' => 'registro_sin_distincion_programacion_ejecucion',
            'fecha_llegada' => $this->fecha($ruta->llegada_confirmada_at), 'fecha_recepcion' => $this->fecha($recepcion)];
    }

    private function agregar(array &$eventos, string $referencia, array $datos): void
    {
        $eventos[$referencia] = ['referencia' => $referencia] + $datos;
    }

    private function fecha($fecha, bool $soloDia = false): ?string
    {
        if ($fecha === null) {
            return null;
        }

        $valor = \Carbon\Carbon::parse($fecha);

        return $soloDia ? $valor->toDateString() : $valor->setTimezone(config('app.timezone'))->toIso8601String();
    }

    private function decimal($valor): ?string
    {
        return $valor === null ? null : InventarioDecimal::texto(InventarioDecimal::unidades($valor));
    }

    private function codigo(?string $valor): ?string
    {
        return $valor === null ? null : strtoupper(trim($valor));
    }
}
