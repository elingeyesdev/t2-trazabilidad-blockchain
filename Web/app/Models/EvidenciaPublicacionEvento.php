<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class EvidenciaPublicacionEvento extends Model
{
    protected $table = 'evidencia_publicacion_evento';

    protected $primaryKey = 'evidenciapublicacioneventoid';

    public $timestamps = false;

    protected $fillable = ['evidenciapublicacionid', 'usuarioid', 'accion', 'motivo', 'fecha'];

    protected $casts = ['evidenciapublicacionid' => 'integer', 'usuarioid' => 'integer', 'fecha' => 'datetime'];
}
