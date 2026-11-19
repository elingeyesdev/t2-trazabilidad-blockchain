<?php

namespace App\Models\Concerns;

use App\Exceptions\EliminacionBloqueadaException;
use Illuminate\Validation\ValidationException;

trait ConservaEmisionCertificado
{
    protected static function bootConservaEmisionCertificado(): void
    {
        static::updating(function ($modelo) {
            $protegidos = ['loteid', 'loteproduccionpedidoid', 'usuarioid', 'inspector_usuarioid',
                'codigo_certificado', 'resultado', 'razon', 'observaciones', 'recomendaciones',
                'fecha_certificacion', 'fecha_evaluacion', 'emision_uuid', 'solicitud_id', 'solicitud_huella',
                'datos_emision', 'archivo_path', 'formato_version'];
            if ($modelo->isDirty($protegidos)) {
                throw ValidationException::withMessages(['certificado' => 'Las emisiones son antecedentes de solo lectura. Registre una nueva emisión.']);
            }
        });
        static::deleting(function () {
            throw new EliminacionBloqueadaException('No se puede eliminar una emisión de certificado.');
        });
    }
}
