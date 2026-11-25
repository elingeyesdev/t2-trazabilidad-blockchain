<?php

namespace App\Support;

use Illuminate\Validation\ValidationException;

final class CodigoTrazabilidadPublica
{
    /** Current dated codes and the UUID used by conserved PDV receipts. */
    public static function normalizar(string $codigo): string
    {
        $codigo = strtoupper(trim($codigo));
        $uuid = '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}';
        $patron = '/\A(?:TRZ-PDV-(?:[0-9]{8}-[A-Z0-9]{6}|'.$uuid.')|(?:TRAZ|TRZ)-[0-9]{8}-[A-Z0-9]{6})\z/D';
        if (strlen($codigo) > 64 || ! preg_match($patron, $codigo)) {
            throw ValidationException::withMessages(['codigo' => 'El código de trazabilidad no tiene un formato admitido (máximo 64 caracteres).']);
        }

        return $codigo;
    }
}
