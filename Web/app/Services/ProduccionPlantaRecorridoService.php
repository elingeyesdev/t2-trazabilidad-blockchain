<?php

namespace App\Services;

use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Models\Usuario;
use App\Support\AlmacenAcceso;
use App\Support\InventarioDecimal;
use App\Support\LoteAcceso;
use App\Support\ProduccionPlantaAcceso;

/** Consulta sin sincronizaciones ni reconstrucción de antecedentes por nombres o fechas. */
final class ProduccionPlantaRecorridoService
{
    public function consultar(LoteProduccionPedido $lote, Usuario $usuario): array
    {
        abort_unless(ProduccionPlantaAcceso::puedeVer($usuario, $lote), 404);
        $lote->load(['materiasPrimas.insumo.unidadMedida', 'materiasPrimas.movimientoConsumo.unidadMedida',
            'materiasPrimas.materiaPrimaLote.detallePedido.pedido.envioAsignacion',
            'materiasPrimas.materiaPrimaLote.detallePedido.cosechaAlmacen.produccion',
            'materiasPrimas.presentacionLote.presentacion.tipoEmpaque', 'almacenajes.almacen',
            'partidasObtenidas.insumo', 'partidasObtenidas.presentacion.tipoEmpaque', 'partidasObtenidas.almacen']);
        $almacenes = $usuario->can('inventario.view') ? AlmacenAcceso::idsVisibles($usuario) : [];
        $visible = fn ($id) => $id !== null && in_array((int) $id, $almacenes, true);
        $campos = Lote::whereKey($lote->materiasPrimas->pluck('materiaPrimaLote.detallePedido.cosechaAlmacen.produccion.loteid')->filter()->unique());
        LoteAcceso::aplicarScopeVisibles($campos, $usuario);
        $campoIds = $usuario->can('lotes.view') ? $campos->pluck('loteid')->map(fn ($id) => (int) $id)->all() : [];
        $industriales = $lote->materiasPrimas->pluck('presentacionLote.loteproduccionpedidoid')->filter()->unique();
        $industrialesVisibles = ProduccionPlantaAcceso::scope(LoteProduccionPedido::whereKey($industriales), $usuario)
            ->pluck('loteproduccionpedidoid')->map(fn ($id) => (int) $id)->all();
        $restricciones = ['origenes' => false, 'destinos' => false, 'ubicaciones_actuales' => false];
        $origenes = [];
        foreach ($lote->materiasPrimas->sortBy('loteproduccionmateriaid') as $materia) {
            $partida = $materia->materiaPrimaLote;
            $industrial = $materia->presentacionLote;
            $insumo = $materia->insumo;
            if (! $insumo || ! $visible($insumo->almacenid)
                || ($partida && (! $visible($partida->almacenid) || (int) $partida->insumoid !== (int) $materia->insumoid))
                || ($industrial && (! $visible($industrial->almacenid) || (int) $industrial->insumoid !== (int) $materia->insumoid))) {
                $restricciones['origenes'] = true;

                continue;
            }
            $movimiento = $materia->movimientoConsumo;
            if ($movimiento && ((int) $movimiento->loteproduccionpedidoid !== (int) $lote->getKey()
                || (int) $movimiento->insumoid !== (int) $materia->insumoid
                || (int) $movimiento->materiaprimaloteid !== (int) $materia->materiaprimaloteid
                || (int) $movimiento->inventario_presentacion_loteid !== (int) $materia->inventario_presentacion_loteid
                || ! $visible($movimiento->almacenid))) {
                $movimiento = null;
            }
            $detalle = $partida?->detallePedido;
            $envio = $detalle?->pedido?->envioAsignacion;
            $linea = $detalle ? collect($envio?->recepcion_planta_datos['lineas'] ?? [])
                ->first(fn ($fila) => (int) ($fila['detallepedidoid'] ?? 0) === (int) $detalle->getKey()
                    && (int) ($fila['materiaprimaloteid'] ?? 0) === (int) $partida->getKey()) : null;
            $campoId = $detalle?->cosechaAlmacen?->produccion?->loteid;
            $campoPermitido = $campoId !== null && in_array((int) $campoId, $campoIds, true);
            $industrialId = $industrial?->loteproduccionpedidoid;
            $industrialPermitido = $industrialId !== null && in_array((int) $industrialId, $industrialesVisibles, true);
            $origenes[] = [
                'consumo_id' => (int) $materia->getKey(), 'insumo_id' => (int) $insumo->getKey(), 'insumo' => $insumo->nombre,
                'almacen_id' => (int) $insumo->almacenid,
                'referencia_partida' => $partida?->lote_proveedor ?: $industrial?->referencia_lote,
                'materiaprimaloteid' => $partida ? (int) $partida->getKey() : null,
                'inventario_presentacion_loteid' => $industrial ? (int) $industrial->getKey() : null,
                'cantidad_consumida' => $this->decimal($materia->getRawOriginal('cantidad_usada')),
                'cantidad_unidades_consumidas' => $this->decimal($materia->getRawOriginal('cantidad_unidades_consumidas')),
                'presentacion' => $industrial?->presentacion?->nombre,
                'unidad_presentacion' => $industrial?->presentacion?->etiquetaUnidad(),
                'unidad_registrada' => $movimiento?->unidadMedida?->abreviatura ?: $movimiento?->unidadMedida?->nombre,
                'unidad_catalogo_actual' => $insumo->unidadMedida?->abreviatura ?: $insumo->unidadMedida?->nombre,
                'movimiento_consumo_id' => $movimiento ? (int) $movimiento->getKey() : null,
                'cantidad_recibida' => $usuario->can('recepcion_planta.view') ? $this->decimal($linea['cantidad_recibida'] ?? null) : null,
                'unidad_recepcion' => $usuario->can('recepcion_planta.view') ? ($linea['unidad'] ?? null) : null,
                'recepcion' => $linea && $usuario->can('recepcion_planta.view') ? [
                    'pedidoid' => (int) $detalle->pedidoid, 'detallepedidoid' => (int) $detalle->getKey(),
                    'fecha' => $envio?->fecha_recepcion_planta?->toIso8601String(),
                ] : null,
                'origen_agricola' => $campoPermitido ? ['loteid' => (int) $campoId,
                    'produccionid' => (int) $detalle->cosechaAlmacen->produccionid] : null,
                'origen_industrial_id' => $industrialPermitido ? (int) $industrialId : null,
                'antecedente_restringido' => ($campoId !== null && ! $campoPermitido) || ($industrialId !== null && ! $industrialPermitido),
            ];
        }
        $ingresos = [];
        foreach ($lote->almacenajes->sortBy('almacenajeloteid') as $ingreso) {
            $datos = $ingreso->datos_ingreso;
            $almacenId = $datos['almacenid'] ?? $ingreso->almacenid;
            if (! $visible($almacenId)) {
                $restricciones['destinos'] = true;

                continue;
            }
            $ingresos[] = [
                'almacenaje_id' => (int) $ingreso->getKey(),
                'insumo_id' => $datos ? (int) $ingreso->insumoid : null,
                'producto' => $datos['producto'] ?? null,
                'presentacion_id' => $datos ? (int) $ingreso->insumo_presentacionid : null,
                'presentacion' => $datos['presentacion'] ?? null,
                'partida_id' => $datos ? (int) $ingreso->inventario_presentacion_loteid : null,
                'cantidad_ingresada' => $this->decimal($datos['cantidad_unidades'] ?? null),
                'unidad' => $datos['unidad'] ?? null, 'cantidad_kg' => $this->decimal($datos['cantidad_kg'] ?? null),
                'almacen_id' => (int) $almacenId, 'almacen' => $datos['almacen'] ?? $ingreso->almacen?->nombre,
                'fecha' => $datos['fecha'] ?? $ingreso->fecha_almacenaje?->toIso8601String(),
                'estado' => $datos ? 'Ingreso registrado' : 'Registro antiguo: cantidad original y producto sin vínculo directo',
            ];
        }
        $ubicaciones = [];
        foreach ($lote->partidasObtenidas->sortBy('inventario_presentacion_loteid') as $partida) {
            if (! $visible($partida->almacenid)) {
                $restricciones['ubicaciones_actuales'] = true;

                continue;
            }
            $ubicaciones[] = ['partida_id' => (int) $partida->getKey(), 'insumo_id' => (int) $partida->insumoid,
                'producto' => $partida->insumo?->nombre, 'presentacion_id' => (int) $partida->insumo_presentacionid,
                'presentacion' => $partida->presentacion?->nombre, 'unidad' => $partida->presentacion?->etiquetaUnidad(),
                'cantidad_actual' => $this->decimal($partida->getRawOriginal('cantidad_unidades')),
                'cantidad_actual_kg' => $this->decimal($partida->getRawOriginal('cantidad_kg')),
                'almacen_id' => (int) $partida->almacenid, 'almacen' => $partida->almacen?->nombre];
        }

        $productos = [];
        foreach ($ingresos as $ingreso) {
            if ($ingreso['partida_id'] !== null) {
                $productos[$ingreso['partida_id']] = ['partida_id' => $ingreso['partida_id'],
                    'insumo_id' => $ingreso['insumo_id'], 'producto' => $ingreso['producto'],
                    'presentacion_id' => $ingreso['presentacion_id'], 'presentacion' => $ingreso['presentacion']];
            }
        }
        foreach ($ubicaciones as $partida) {
            if (! isset($productos[$partida['partida_id']])) {
                $productos[$partida['partida_id']] = array_intersect_key($partida, array_flip([
                    'partida_id', 'insumo_id', 'producto', 'presentacion_id', 'presentacion']));
            }
        }

        return ['nivel' => 'lote_produccion', 'lote_produccion' => [
            'id' => (int) $lote->getKey(), 'codigo' => $lote->codigo_lote, 'nombre' => $lote->nombre,
        ], 'productos_obtenidos' => array_values($productos), 'origenes' => $origenes, 'ingresos_produccion' => $ingresos,
            'ubicaciones_actuales' => $ubicaciones, 'restricciones' => $restricciones];
    }

    private function decimal(mixed $valor): ?string
    {
        return $valor === null ? null : InventarioDecimal::texto(InventarioDecimal::unidades($valor));
    }
}
