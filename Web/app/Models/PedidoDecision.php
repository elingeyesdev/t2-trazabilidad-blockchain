<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PedidoDecision extends Model
{
    protected $table = 'pedido_decision';

    protected $primaryKey = 'pedidodecisionid';

    public $timestamps = false;

    protected $fillable = ['pedidoid', 'pedidodistribucionid', 'usuarioid', 'secuencia', 'accion', 'estado_anterior', 'estado_resultante', 'motivo', 'fecha'];

    protected $casts = ['fecha' => 'datetime', 'usuarioid' => 'integer', 'secuencia' => 'integer'];
}
