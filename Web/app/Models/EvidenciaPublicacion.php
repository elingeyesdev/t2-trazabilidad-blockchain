<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class EvidenciaPublicacion extends Model
{
    protected $table = 'evidencia_publicacion';

    protected $primaryKey = 'evidenciapublicacionid';

    protected $fillable = ['actividadid', 'loteproduccionpedidoid', 'solicitadopor_usuarioid', 'estado',
        'origen_sha256', 'token_publico', 'archivo_sanitizado', 'aprobado_en', 'retirado_en'];

    protected $casts = ['actividadid' => 'integer', 'loteproduccionpedidoid' => 'integer', 'solicitadopor_usuarioid' => 'integer',
        'aprobado_en' => 'datetime', 'retirado_en' => 'datetime'];

    public function actividad()
    {
        return $this->belongsTo(Actividad::class, 'actividadid', 'actividadid');
    }

    public function loteProduccion()
    {
        return $this->belongsTo(LoteProduccionPedido::class, 'loteproduccionpedidoid', 'loteproduccionpedidoid');
    }

    public function eventos()
    {
        return $this->hasMany(EvidenciaPublicacionEvento::class, 'evidenciapublicacionid', 'evidenciapublicacionid');
    }
}
