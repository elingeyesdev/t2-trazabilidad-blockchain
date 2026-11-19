<?php

namespace App\Support;

use Illuminate\Validation\ValidationException;

final class RecepcionFirmaImagen
{
    /** PNG real de la firma manuscrita; no es una firma digital certificada. */
    public static function decodificar(mixed $valor): string
    {
        $error = fn () => throw ValidationException::withMessages(['imagen_firma' => 'Dibuje una firma PNG válida, no vacía y de hasta 1 MB.']);
        if (! is_string($valor) || strlen($valor) > 1400000 || ! str_starts_with($valor, 'data:image/png;base64,')) {
            $error();
        }
        $bytes = base64_decode(substr($valor, 22), true);
        $info = $bytes === false ? false : @getimagesizefromstring($bytes);
        if (! $info || $info[2] !== IMAGETYPE_PNG || strlen($bytes) > 1048576 || $info[0] > 2048 || $info[1] > 2048 || $info[0] < 2 || $info[1] < 2) {
            $error();
        }
        $imagen = @imagecreatefromstring($bytes);
        if (! $imagen) {
            $error();
        }
        $tinta = false;
        for ($y = 0; $y < imagesy($imagen) && ! $tinta; $y++) {
            for ($x = 0; $x < imagesx($imagen); $x++) {
                $color = imagecolorsforindex($imagen, imagecolorat($imagen, $x, $y));
                if ($color['alpha'] < 120 && min($color['red'], $color['green'], $color['blue']) < 220) {
                    $tinta = true;
                    break;
                }
            }
        }
        imagedestroy($imagen);
        if (! $tinta) {
            $error();
        }

        return $bytes;
    }
}
