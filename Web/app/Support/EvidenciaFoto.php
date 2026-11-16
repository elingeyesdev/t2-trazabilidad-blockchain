<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;

class EvidenciaFoto
{
    public static function guardar(UploadedFile $file, string $carpeta): string
    {
        return $file->store($carpeta, 'public');
    }

    public static function urlDesdePath(?string $path, ?int $actividadid = null): ?string
    {
        if ($path === null || trim($path) === '') {
            return null;
        }

        if (preg_match('#^actividades_privadas/([0-9]+)/#', $path, $matches)) {
            return route('actividades.evidencia', ['actividad' => $matches[1]]);
        }

        if (str_starts_with($path, 'actividades_evidencia/')) {
            return $actividadid ? route('actividades.evidencia', ['actividad' => $actividadid]) : null;
        }

        return asset('storage/'.ltrim($path, '/'));
    }

    public static function urlDesdeImagenUrl(?string $imagenurl): ?string
    {
        if ($imagenurl === null || trim($imagenurl) === '') {
            return null;
        }

        if (str_starts_with($imagenurl, 'http://') || str_starts_with($imagenurl, 'https://')) {
            return $imagenurl;
        }

        return asset(ltrim($imagenurl, '/'));
    }
}
