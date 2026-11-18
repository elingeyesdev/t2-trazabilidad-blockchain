<?php

namespace App\Http\Resources\Api;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class InventarioMovimientoResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['almacen_movimientoid' => $this->almacen_movimientoid, 'almacenid' => $this->almacenid,
            'insumoid' => $this->insumoid, 'tipo_movimiento_almacenid' => $this->tipo_movimiento_almacenid,
            'usuarioid' => $this->usuarioid, 'fecha' => $this->fecha?->toDateString(), 'cantidad' => $this->cantidad,
            'referencia' => $this->referencia, 'destino_motivo' => $this->destino_motivo, 'observaciones' => $this->observaciones,
            'materiaprimaloteid' => $this->materiaprimaloteid, 'partida' => $this->partida?->lote_proveedor ?? $this->presentacionLote?->referencia_lote,
            'inventario_presentacion_loteid' => $this->inventario_presentacion_loteid,
            'unidadmedidaid' => $this->unidadmedidaid, 'unidad' => $this->unidadMedida?->abreviatura,
            'unidad_historica' => $this->unidadmedidaid !== null,
            'saldo_anterior' => $this->saldo_anterior, 'saldo_posterior' => $this->saldo_posterior,
            'insumo' => ['insumoid' => $this->insumoid, 'nombre' => $this->insumo?->nombre],
            'tipo' => ['nombre' => $this->tipo?->nombre, 'naturaleza' => $this->tipo?->naturaleza],
            'usuario' => $this->usuario ? ['usuarioid' => $this->usuarioid, 'nombre' => $this->usuario->nombre, 'apellido' => $this->usuario->apellido] : null];
    }
}
