<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class AlmacenMovimiento extends Model
{
    use HasFactory;

    protected $table = 'almacen_movimiento';
    protected $primaryKey = 'almacen_movimientoid';

    protected $fillable = [
        'almacenid',
        'insumoid',
        'tipo_movimiento_almacenid',
        'usuarioid',
        'fecha',
        'cantidad',
        'referencia',
        'destino_motivo',
        'observaciones',
        'detallepedidodistribucionid',
        'materiaprimaloteid', 'unidadmedidaid', 'saldo_anterior', 'saldo_posterior',
        'inventario_presentacion_loteid',
        'insumo_presentacionid', 'cantidad_unidades', 'loteproduccionpedidoid',
    ];

    protected $casts = [
        'almacenid' => 'integer',
        'insumoid' => 'integer',
        'tipo_movimiento_almacenid' => 'integer',
        'usuarioid' => 'integer',
        'fecha' => 'date',
        'cantidad' => 'decimal:6',
        'saldo_anterior' => 'decimal:6',
        'saldo_posterior' => 'decimal:6',
    ];

    public function almacen()
    {
        return $this->belongsTo(Almacen::class, 'almacenid', 'almacenid');
    }

    public function setCantidadAttribute($cantidad): void
    {
        $texto = \App\Support\InventarioDecimal::texto(\App\Support\InventarioDecimal::unidades($cantidad));
        $this->attributes['cantidad'] = rtrim(rtrim($texto, '0'), '.');
    }

    public function partida()
    {
        return $this->belongsTo(MateriaPrimaLote::class, 'materiaprimaloteid', 'materiaprimaloteid');
    }

    public function presentacionLote()
    {
        return $this->belongsTo(InventarioPresentacionLote::class, 'inventario_presentacion_loteid', 'inventario_presentacion_loteid');
    }

    public function unidadMedida()
    {
        return $this->belongsTo(UnidadMedida::class, 'unidadmedidaid', 'unidadmedidaid');
    }

    public function insumo()
    {
        return $this->belongsTo(Insumo::class, 'insumoid', 'insumoid');
    }

    public function tipo()
    {
        return $this->belongsTo(TipoMovimientoAlmacen::class, 'tipo_movimiento_almacenid', 'tipo_movimiento_almacenid');
    }

    public function usuario()
    {
        return $this->belongsTo(Usuario::class, 'usuarioid', 'usuarioid');
    }
}
