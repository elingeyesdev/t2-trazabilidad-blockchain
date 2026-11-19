<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class LoteProduccionMateriaPrima extends Model
{
    protected $table = 'lote_produccion_materia_prima';
    protected $primaryKey = 'loteproduccionmateriaid';

    protected $fillable = [
        'loteproduccionpedidoid',
        'materiaprimaloteid',
        'insumoid',
        'inventario_presentacion_loteid',
        'cantidad_unidades_consumidas',
        'cantidad_planificada',
        'cantidad_usada',
    ];

    protected $casts = [
        'cantidad_planificada' => 'decimal:6',
        'cantidad_usada'       => 'decimal:6',
        'cantidad_unidades_consumidas' => 'decimal:6',
    ];

    public function presentacionLote(): BelongsTo
    {
        return $this->belongsTo(InventarioPresentacionLote::class, 'inventario_presentacion_loteid', 'inventario_presentacion_loteid');
    }

    public function loteProduccionPedido(): BelongsTo
    {
        return $this->belongsTo(LoteProduccionPedido::class, 'loteproduccionpedidoid', 'loteproduccionpedidoid');
    }

    public function materiaPrimaLote(): BelongsTo
    {
        return $this->belongsTo(MateriaPrimaLote::class, 'materiaprimaloteid', 'materiaprimaloteid');
    }

    public function insumo(): BelongsTo
    {
        return $this->belongsTo(Insumo::class, 'insumoid', 'insumoid');
    }
}
