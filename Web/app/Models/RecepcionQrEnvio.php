<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RecepcionQrEnvio extends Model
{
    protected $table = 'recepcion_qr_envio';

    protected $primaryKey = 'recepcionqrenvioid';

    protected $hidden = ['token', 'token_cifrado', 'firma_path', 'datos_recepcion'];

    protected $casts = [
        'token_cifrado' => 'encrypted',
        'utilizado_en' => 'datetime',
        'datos_recepcion' => 'array',
        'destinatario_usuarioid' => 'integer',
    ];

    public function getTokenAttribute($value): string
    {
        return $this->token_cifrado ?? $value;
    }

    protected $fillable = [
        'token',
        'rutadistribucionid',
        'envioasignacionmultipleid',
    ];

    public function ruta(): BelongsTo
    {
        return $this->belongsTo(RutaDistribucion::class, 'rutadistribucionid', 'rutadistribucionid');
    }

    public function asignacion(): BelongsTo
    {
        return $this->belongsTo(EnvioAsignacionMultiple::class, 'envioasignacionmultipleid', 'envioasignacionmultipleid');
    }
}
