<?php

namespace App\Services;

use App\Models\Actividad;
use App\Models\EvidenciaPublicacion;
use App\Models\LoteProduccionPedido;
use App\Models\Usuario;
use App\Support\LoteAcceso;
use App\Support\ProduccionPlantaAcceso;
use App\Support\UsuarioRol;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class EvidenciaPublicacionService
{
    private const PUBLICADAS = ['publicada', 'retiro_solicitado'];

    public function solicitar(Usuario $usuario, Actividad $actividad, string $motivo, ?int $loteProduccionId = null): EvidenciaPublicacion
    {
        $motivo = $this->motivo($motivo);

        return DB::transaction(function () use ($usuario, $actividad, $motivo, $loteProduccionId) {
            $this->bloquearActividad((int) $actividad->getKey());
            $actual = Actividad::whereKey($actividad->getKey())->lockForUpdate()->firstOrFail();
            $this->autorizarSolicitud($usuario, $actual, $loteProduccionId);
            $archivo = $this->fuente($actual);
            $this->validarImagen($archivo);
            $hash = hash_file('sha256', $archivo);
            $anterior = EvidenciaPublicacion::where('actividadid', $actual->getKey())
                ->where('origen_sha256', $hash)->where('loteproduccionpedidoid', $loteProduccionId)
                ->whereIn('estado', ['solicitada', ...self::PUBLICADAS])->lockForUpdate()->orderByDesc('evidenciapublicacionid')->first();
            if ($anterior) {
                return $anterior;
            }
            $publicacion = EvidenciaPublicacion::create([
                'actividadid' => $actual->getKey(), 'loteproduccionpedidoid' => $loteProduccionId,
                'solicitadopor_usuarioid' => $usuario->getKey(), 'estado' => 'solicitada',
                'origen_sha256' => $hash, 'token_publico' => (string) Str::uuid(),
            ]);
            $this->evento($publicacion, $usuario, 'solicitar', $motivo);

            return $publicacion;
        }, 5);
    }

    public function solicitarRetiro(Usuario $usuario, int $id, string $motivo): EvidenciaPublicacion
    {
        $motivo = $this->motivo($motivo);

        return DB::transaction(function () use ($usuario, $id, $motivo) {
            $publicacion = $this->bloquearPublicacion($id, $usuario);
            if (UsuarioRol::gestionaCampo($usuario)) {
                // The agricultural owner may request withdrawal of their source photograph,
                // including when its publication was requested from a linked plant context.
                abort_unless($publicacion->actividad?->lote && LoteAcceso::puedeGestionar($usuario, $publicacion->actividad->lote), 404);
            } else {
                $this->autorizarSolicitud($usuario, $publicacion->actividad, $publicacion->loteproduccionpedidoid);
            }
            if (in_array($publicacion->estado, ['retiro_solicitado', 'retirada'], true)) {
                return $publicacion;
            }
            if ($publicacion->estado !== 'publicada') {
                throw new ConflictHttpException('Solo se puede solicitar el retiro de una evidencia publicada.');
            }
            $publicacion->update(['estado' => 'retiro_solicitado']);
            $this->evento($publicacion, $usuario, 'solicitar_retiro', $motivo);

            return $publicacion;
        }, 5);
    }

    public function aprobar(Usuario $usuario, int $id, string $motivo): EvidenciaPublicacion
    {
        $this->autorizarAdministrador($usuario);
        $motivo = $this->motivo($motivo);
        $creados = [];
        try {
            $publicacion = DB::transaction(function () use ($usuario, $id, $motivo, &$creados) {
                $publicacion = $this->bloquearPublicacion($id, $usuario);
                if (in_array($publicacion->estado, self::PUBLICADAS, true)) {
                    return $publicacion;
                }
                if ($publicacion->estado !== 'solicitada') {
                    throw new ConflictHttpException('La solicitud ya fue retirada. Registre una nueva solicitud.');
                }
                $this->bloquearActividad((int) $publicacion->actividadid);
                Actividad::whereKey($publicacion->actividadid)->lockForUpdate()->firstOrFail();
                $otra = EvidenciaPublicacion::where('actividadid', $publicacion->actividadid)
                    ->where('evidenciapublicacionid', '!=', $publicacion->getKey())
                    ->whereIn('estado', self::PUBLICADAS)->lockForUpdate()->first();
                if ($otra) {
                    throw new ConflictHttpException('Ya existe una publicación activa para esta evidencia. Retírela antes de aprobar otra.');
                }
                $archivo = $this->fuente($publicacion->actividad);
                if (! hash_equals((string) $publicacion->origen_sha256, (string) hash_file('sha256', $archivo))) {
                    throw ValidationException::withMessages(['evidencia' => 'La fotografía cambió desde la solicitud. Solicite su publicación nuevamente.']);
                }
                $this->validarContextoPlanta($publicacion->actividad, $publicacion->loteproduccionpedidoid);
                $path = 'evidencias_publicadas/'.Str::uuid().'.png';
                $this->sanitizar($archivo, $path);
                $creados[] = $path;
                // The approved bytes and the original fingerprint must describe the same source version.
                if (! hash_equals((string) $publicacion->origen_sha256, (string) hash_file('sha256', $archivo))) {
                    throw ValidationException::withMessages(['evidencia' => 'La fotografía cambió durante la revisión.']);
                }
                $publicacion->update(['estado' => 'publicada', 'archivo_sanitizado' => $path, 'aprobado_en' => now()]);
                $this->evento($publicacion, $usuario, 'aprobar', $motivo);

                return $publicacion;
            }, 5);
        } catch (\Throwable $exception) {
            foreach ($creados as $path) {
                Storage::disk('local')->delete($path);
            }
            throw $exception;
        }
        foreach ($creados as $path) {
            if ($path !== $publicacion->archivo_sanitizado) {
                Storage::disk('local')->delete($path);
            }
        }

        return $publicacion;
    }

    public function retirar(Usuario $usuario, int $id, string $motivo): EvidenciaPublicacion
    {
        $this->autorizarAdministrador($usuario);
        $motivo = $this->motivo($motivo);

        return DB::transaction(function () use ($usuario, $id, $motivo) {
            $publicacion = $this->bloquearPublicacion($id, $usuario);
            if ($publicacion->estado === 'retirada') {
                return $publicacion;
            }
            $publicacion->update(['estado' => 'retirada', 'retirado_en' => now()]);
            $this->evento($publicacion, $usuario, 'retirar', $motivo);

            return $publicacion;
        }, 5);
    }

    public function consulta(Usuario $usuario): Builder
    {
        $this->autorizarCuenta($usuario);
        $query = EvidenciaPublicacion::query();
        if (UsuarioRol::esAdminGlobal($usuario) && $usuario->can('evidencias.publicar')) {
            return $query;
        }
        if (UsuarioRol::gestionaCampo($usuario) && $usuario->can('lotes.view')) {
            return $query->whereHas('actividad.lote', fn (Builder $lotes) => $lotes->whereIn('usuarioid', UsuarioRol::idsUsuariosBajoJefeAgricultor($usuario)));
        }
        if (UsuarioRol::gestionaPlanta($usuario)) {
            return $query->whereHas('loteProduccion', fn (Builder $lotes) => ProduccionPlantaAcceso::scope($lotes, $usuario));
        }

        return $query->whereRaw('1 = 0');
    }

    /** Public metadata only; no source path, operator, approval reason or authorizing QR token. */
    public function visibles(Collection $actividades): array
    {
        $actividades = $actividades->filter(fn ($a) => $a instanceof Actividad)->keyBy(fn ($a) => $a->getKey());
        if ($actividades->isEmpty()) {
            return [];
        }
        $publicaciones = EvidenciaPublicacion::whereIn('actividadid', $actividades->keys())
            ->whereIn('estado', self::PUBLICADAS)->whereNotNull('aprobado_en')
            ->orderByDesc('aprobado_en')->orderByDesc('evidenciapublicacionid')->get();
        $visibles = [];
        foreach ($publicaciones as $publicacion) {
            $id = $publicacion->actividadid;
            if (isset($visibles[$id]) || ! $this->publicacionDisponible($publicacion, $actividades[$id])) {
                continue;
            }
            $visibles[$id] = ['referencia' => 'actividad:'.$id, 'tipo' => 'imagen',
                'url' => route('api.trazabilidad.evidencia', ['token' => $publicacion->token_publico]),
                'fecha_publicacion' => $publicacion->aprobado_en->toIso8601String()];
        }

        return array_values($visibles);
    }

    public function archivoPublico(string $token): BinaryFileResponse
    {
        $ausente = 'No hay evidencia pública disponible para este enlace.';
        abort_unless(Str::isUuid($token), 404, $ausente);
        $publicacion = EvidenciaPublicacion::where('token_publico', $token)->whereIn('estado', self::PUBLICADAS)
            ->with('actividad')->first();
        abort_unless($publicacion && $publicacion->actividad && $this->publicacionDisponible($publicacion, $publicacion->actividad), 404, $ausente);
        $archivo = $this->sanitizado($publicacion);
        abort_unless($archivo !== null, 404, $ausente);

        return $this->respuestaArchivo($archivo);
    }

    public function revisarArchivo(Usuario $usuario, int $id): BinaryFileResponse
    {
        if (UsuarioRol::esAdminGlobal($usuario)) {
            $this->autorizarAdministrador($usuario);
        } else {
            abort_unless(UsuarioRol::gestionaCampo($usuario) || UsuarioRol::gestionaPlanta($usuario), 403);
        }
        $publicacion = $this->consulta($usuario)->with('actividad')->findOrFail($id);
        abort_unless($publicacion->actividad, 404);
        if (UsuarioRol::gestionaPlanta($usuario)) {
            $this->autorizarSolicitud($usuario, $publicacion->actividad, $publicacion->loteproduccionpedidoid);
        }

        return $this->respuestaArchivo($this->fuente($publicacion->actividad), false);
    }

    private function autorizarAdministrador(Usuario $usuario): void
    {
        $this->autorizarCuenta($usuario);
        // Publication administration is expressly authorized metadata management, not business execution.
        abort_unless(UsuarioRol::esAdminGlobal($usuario) && $usuario->can('evidencias.publicar'), 403);
    }

    private function autorizarSolicitud(Usuario $usuario, Actividad $actividad, ?int $loteProduccionId): void
    {
        $this->autorizarCuenta($usuario);
        if (UsuarioRol::gestionaCampo($usuario) && $loteProduccionId === null) {
            abort_unless($usuario->can('lotes.view'), 403);
            abort_unless($actividad->lote && LoteAcceso::puedeGestionar($usuario, $actividad->lote), 404);

            return;
        }
        abort_unless(UsuarioRol::gestionaPlanta($usuario) && $loteProduccionId !== null, 403);
        ProduccionPlantaAcceso::scope(LoteProduccionPedido::query(), $usuario)->findOrFail($loteProduccionId);
        $this->validarContextoPlanta($actividad, $loteProduccionId);
    }

    private function validarContextoPlanta(Actividad $actividad, ?int $loteProduccionId): void
    {
        if ($loteProduccionId !== null) {
            abort_unless(LoteProduccionPedido::whereKey($loteProduccionId)
                ->whereHas('materiasPrimas.materiaPrimaLote.detallePedido.cosechaAlmacen.produccion',
                    fn (Builder $producciones) => $producciones->where('loteid', $actividad->loteid))->exists(), 404);
        }
    }

    private function autorizarCuenta(Usuario $usuario): void
    {
        abort_unless(\App\Support\CuentaEstado::puedeIniciarSesion(
            $usuario->estado_cuenta ?? \App\Support\CuentaEstado::APROBADO, (bool) $usuario->activo), 403);
    }

    private function bloquearActividad(int $id): void
    {
        if (DB::getDriverName() === 'sqlite') {
            DB::table('actividad')->where('actividadid', $id)->update(['actividadid' => DB::raw('actividadid')]);
        }
    }

    private function bloquearPublicacion(int $id, Usuario $usuario): EvidenciaPublicacion
    {
        if (DB::getDriverName() === 'sqlite') {
            DB::table('evidencia_publicacion')->where('evidenciapublicacionid', $id)
                ->update(['evidenciapublicacionid' => DB::raw('evidenciapublicacionid')]);
        }

        return $this->consulta($usuario)->with('actividad')->lockForUpdate()->findOrFail($id);
    }

    private function evento(EvidenciaPublicacion $publicacion, Usuario $usuario, string $accion, string $motivo): void
    {
        $publicacion->eventos()->create(['usuarioid' => $usuario->getKey(), 'accion' => $accion, 'motivo' => $motivo, 'fecha' => now()]);
    }

    private function motivo(string $motivo): string
    {
        $motivo = trim($motivo);
        if ($motivo === '' || mb_strlen($motivo) > 1000) {
            throw ValidationException::withMessages(['motivo' => 'Indique un motivo de hasta 1000 caracteres.']);
        }

        return $motivo;
    }

    private function fuente(Actividad $actividad): string
    {
        $path = (string) $actividad->evidencia_foto_path;
        $archivo = null;
        if (preg_match('#^actividades_privadas/'.(int) $actividad->getKey().'/[A-Za-z0-9_-]+\.(?:jpe?g|png|webp)$#iD', $path)) {
            $archivo = $this->pathSeguro('local', $path);
        } elseif (preg_match('#^actividades_evidencia/[A-Za-z0-9_-]+\.(?:jpe?g|png|webp)$#iD', $path)) {
            $archivo = $this->pathSeguro('public', $path);
        }
        if ($archivo === null) {
            throw ValidationException::withMessages(['evidencia' => 'No existe una fotografía local válida para publicar.']);
        }

        return $archivo;
    }

    private function pathSeguro(string $disk, string $path): ?string
    {
        $raiz = realpath(Storage::disk($disk)->path(''));
        $archivo = realpath(Storage::disk($disk)->path($path));
        if (! $raiz || ! $archivo || ! is_file($archivo) ||
            ! str_starts_with(str_replace('\\', '/', $archivo), rtrim(str_replace('\\', '/', $raiz), '/').'/')) {
            return null;
        }

        return $archivo;
    }

    private function validarImagen(string $archivo): array
    {
        $dimensiones = @getimagesize($archivo);
        $tamano = filesize($archivo);
        if ($tamano === false || $tamano > 5 * 1024 * 1024 || $tamano === 0 || ! $dimensiones ||
            ! in_array($dimensiones[2], [IMAGETYPE_JPEG, IMAGETYPE_PNG, IMAGETYPE_WEBP], true) ||
            $dimensiones[0] <= 0 || $dimensiones[1] <= 0 || $dimensiones[0] * $dimensiones[1] > 20000000) {
            throw ValidationException::withMessages(['evidencia' => 'La fotografía debe ser JPG, PNG o WebP, de hasta 5 MB y 20 megapíxeles.']);
        }

        return $dimensiones;
    }

    private function sanitizar(string $archivo, string $path): void
    {
        [$ancho, $alto] = $this->validarImagen($archivo);
        if (! function_exists('imagecreatefromstring')) {
            throw ValidationException::withMessages(['evidencia' => 'No está disponible el procesamiento seguro de fotografías.']);
        }
        $origen = @imagecreatefromstring(file_get_contents($archivo));
        if ($origen === false) {
            throw ValidationException::withMessages(['evidencia' => 'No se pudo procesar la fotografía.']);
        }
        $limpia = imagecreatetruecolor($ancho, $alto);
        try {
            imagealphablending($limpia, false);
            imagesavealpha($limpia, true);
            imagecopy($limpia, $origen, 0, 0, 0, 0, $ancho, $alto);
            ob_start();
            try {
                $ok = imagepng($limpia);
                $bytes = ob_get_contents();
            } finally {
                ob_end_clean();
            }
            if (! $ok || ! is_string($bytes) || ! Storage::disk('local')->put($path, $bytes)) {
                throw new \RuntimeException('No se pudo guardar la copia pública sanitizada.');
            }
        } finally {
            imagedestroy($origen);
            imagedestroy($limpia);
        }
    }

    private function sanitizado(EvidenciaPublicacion $publicacion): ?string
    {
        $path = (string) $publicacion->archivo_sanitizado;

        return preg_match('#^evidencias_publicadas/[A-Za-z0-9_-]+\.png$#D', $path)
            ? $this->pathSeguro('local', $path) : null;
    }

    private function publicacionDisponible(EvidenciaPublicacion $publicacion, Actividad $actividad): bool
    {
        try {
            $archivo = $this->sanitizado($publicacion);
            $tipo = $archivo ? @getimagesize($archivo) : false;

            return $publicacion->aprobado_en !== null && $archivo !== null && $tipo && $tipo[2] === IMAGETYPE_PNG
                && hash_equals((string) $publicacion->origen_sha256, (string) hash_file('sha256', $this->fuente($actividad)));
        } catch (\Throwable) {
            return false;
        }
    }

    private function respuestaArchivo(string $archivo, bool $png = true): BinaryFileResponse
    {
        if (! $png) {
            $tipo = $this->validarImagen($archivo)['mime'];
        }
        $respuesta = response()->file($archivo, ['Content-Type' => $png ? 'image/png' : $tipo,
            'X-Content-Type-Options' => 'nosniff', 'Content-Security-Policy' => "default-src 'none'; sandbox"]);
        $respuesta->headers->set('Cache-Control', 'no-store, private');

        return $respuesta;
    }
}
