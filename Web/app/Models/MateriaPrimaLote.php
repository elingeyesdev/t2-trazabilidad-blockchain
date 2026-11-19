<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class MateriaPrimaLote extends Model
{
    protected $table = 'materia_prima_lote';
    protected $primaryKey = 'materiaprimaloteid';

    protected $fillable = [
        'materiaprimabaseid', 'proveedor_actorid', 'lote_proveedor', 'numero_factura',
        'fecha_recepcion', 'fecha_vencimiento', 'cantidad', 'cantidad_disponible',
        'conformidad_recepcion', 'observaciones',
        'insumoid', 'almacenid', 'detallepedidoid',
    ];

    protected $casts = [
        'fecha_recepcion'       => 'date',
        'fecha_vencimiento'     => 'date',
        'cantidad'              => 'decimal:6',
        'cantidad_disponible'   => 'decimal:6',
        'conformidad_recepcion' => 'boolean',
    ];

    public function detallePedido(): BelongsTo
    {
        return $this->belongsTo(DetallePedido::class, 'detallepedidoid', 'detallepedidoid');
    }

    public function materiaBase(): BelongsTo
    {
        return $this->belongsTo(MateriaPrimaBase::class, 'materiaprimabaseid', 'materiaprimabaseid');
    }

    public function insumo(): BelongsTo
    {
        return $this->belongsTo(Insumo::class, 'insumoid', 'insumoid');
    }

    public function almacen(): BelongsTo
    {
        return $this->belongsTo(Almacen::class, 'almacenid', 'almacenid');
    }

    public function proveedor(): BelongsTo
    {
        return $this->belongsTo(ActorAbastecimiento::class, 'proveedor_actorid', 'actorid');
    }

    public function consumosLoteProduccionPedido(): HasMany
    {
        return $this->hasMany(LoteProduccionMateriaPrima::class, 'materiaprimaloteid', 'materiaprimaloteid');
    }
}
