<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AlmacenajeLoteProduccion extends Model
{
    protected $table = 'almacenaje_lote_produccion';
    protected $primaryKey = 'almacenajeloteid';

    protected $fillable = [
        'loteproduccionpedidoid',
        'almacenid',
        'ubicacion',
        'condicion',
        'cantidad',
        'observaciones',
        'latitud_recojo',
        'longitud_recojo',
        'direccion_recojo',
        'referencia_recojo',
        'fecha_almacenaje',
        'fecha_retiro',
    ];

    protected $casts = [
        'datos_ingreso' => 'array',
        'almacenid'         => 'integer',
        'cantidad'          => 'float',
        'latitud_recojo'    => 'float',
        'longitud_recojo'   => 'float',
        'fecha_almacenaje'  => 'datetime',
        'fecha_retiro'      => 'datetime',
    ];

    public function loteProduccionPedido(): BelongsTo
    {
        return $this->belongsTo(LoteProduccionPedido::class, 'loteproduccionpedidoid', 'loteproduccionpedidoid');
    }

    public function producto(): BelongsTo
    {
        return $this->belongsTo(Insumo::class, 'insumoid', 'insumoid');
    }

    public function presentacion(): BelongsTo
    {
        return $this->belongsTo(InsumoPresentacion::class, 'insumo_presentacionid', 'insumo_presentacionid');
    }

    public function partidaGenerada(): BelongsTo
    {
        return $this->belongsTo(InventarioPresentacionLote::class, 'inventario_presentacion_loteid', 'inventario_presentacion_loteid');
    }

    protected static function booted(): void
    {
        static::updating(function ($registro) {
            if ($registro->getRawOriginal('datos_ingreso') !== null && $registro->isDirty(['datos_ingreso', 'insumoid', 'insumo_presentacionid', 'inventario_presentacion_loteid', 'loteproduccionpedidoid'])) {
                throw \Illuminate\Validation\ValidationException::withMessages(['almacenaje' => 'El origen del ingreso registrado no se puede reemplazar.']);
            }
        });
    }

    public function almacen(): BelongsTo
    {
        return $this->belongsTo(Almacen::class, 'almacenid', 'almacenid');
    }
}
