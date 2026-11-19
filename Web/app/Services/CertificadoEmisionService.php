<?php

namespace App\Services;

use App\Models\CertificacionLote;
use App\Models\EstadoLoteTipo;
use App\Models\EvaluacionFinalLoteProduccion;
use App\Models\HistorialEstadoLote;
use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Models\Usuario;
use App\Services\Blockchain\CertificacionBlockchainService;
use App\Services\Blockchain\CertificacionLotePayloadBuilder;
use App\Support\CertificadoAcceso;
use App\Support\LoteAcceso;
use App\Support\LoteProduccionTrazabilidadService;
use App\Support\LoteTrazabilidadService;
use App\Support\ProductoAntecedentesService;
use App\Support\UsuarioRol;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class CertificadoEmisionService
{
    public function __construct(private ProductoAntecedentesService $antecedentes, private CertificadoDocumentoService $documento) {}

    public function emitirCampo(Usuario $usuario, Lote $lote, array $datos): CertificacionLote
    {
        return $this->emitir('campo', $usuario, $lote, $datos);
    }

    public function emitirPlanta(Usuario $usuario, LoteProduccionPedido $lote, array $datos): EvaluacionFinalLoteProduccion
    {
        return $this->emitir('planta', $usuario, $lote, $datos);
    }

    private function emitir(string $ambito, Usuario $usuario, Model $lote, array $entrada): Model
    {
        $resultado = $entrada[$ambito === 'campo' ? 'resultado' : 'razon'] ?? CertificacionLote::RAZON_CERTIFICADO;
        if (! in_array($resultado, CertificacionLote::RAZONES, true)) {
            throw ValidationException::withMessages(['resultado' => 'Seleccione un resultado válido.']);
        }
        $entrada = ['resultado' => $resultado, 'observaciones' => $entrada['observaciones'] ?? null,
            'recomendaciones' => $entrada['recomendaciones'] ?? null, 'solicitud_id' => $entrada['solicitud_id'] ?? null];
        if ($resultado === CertificacionLote::RAZON_NO_CONFORME && blank($entrada['observaciones'])) {
            throw ValidationException::withMessages(['observaciones' => 'Indique el motivo del no conforme.']);
        }
        $huella = hash('sha256', json_encode([$ambito, $lote->getKey(), $resultado, $entrada['observaciones'], $entrada['recomendaciones']], JSON_THROW_ON_ERROR));
        $tipo = $ambito === 'campo' ? CertificacionLote::class : EvaluacionFinalLoteProduccion::class;
        $emisor = $ambito === 'campo' ? 'usuarioid' : 'inspector_usuarioid';
        $uuid = (string) Str::ulid();
        $codigo = ($ambito === 'campo' ? ($resultado === CertificacionLote::RAZON_NO_CONFORME ? 'NCONF' : 'CERT') : 'PLANTA')
            .'-'.now()->format('Y').'-'.$lote->getKey().'-'.$uuid;
        $fecha = now();
        $capturar = function () use ($ambito, $usuario, $lote, $entrada, $huella, $tipo, $emisor, $codigo, $fecha) {
            $actual = $this->bloquear($lote, $usuario);
            $this->autorizar($ambito, $usuario, $actual);
            if ($entrada['solicitud_id']) {
                $anterior = $tipo::where($emisor, $usuario->getKey())->where('solicitud_id', $entrada['solicitud_id'])->first();
                if ($anterior) {
                    if (! hash_equals((string) $anterior->solicitud_huella, $huella)) {
                        throw new ConflictHttpException('La solicitud ya corresponde a otra emisión o contiene otros datos.');
                    }

                    return $anterior;
                }
            }
            $this->requisitos($ambito, $usuario, $actual);
            $recorrido = $ambito === 'campo' ? $this->antecedentes->campo($actual, $usuario) : $this->antecedentes->planta($actual, $usuario);
            $base = null;
            if ($ambito === 'campo') {
                $temporal = new CertificacionLote(['codigo_certificado' => $codigo, 'resultado' => $entrada['resultado'], 'fecha_certificacion' => $fecha]);
                $temporal->setRelation('lote', $actual);
                $base = app(CertificacionLotePayloadBuilder::class)->payloadSinHash($temporal);
            }

            return [$actual, $recorrido, $base];
        };
        $captura = DB::transaction($capturar, 5);
        if ($captura instanceof Model) {
            return $captura;
        }
        [$actual, $recorrido, $base] = $captura;
        $datos = ['formato_version' => CertificadoDocumentoService::VERSION, 'ambito' => $ambito,
            'emision' => ['uuid' => $uuid, 'codigo' => $codigo, 'fecha' => $fecha->toIso8601String(), 'resultado' => $resultado,
                'observaciones' => $entrada['observaciones'], 'recomendaciones' => $entrada['recomendaciones'],
                'emisor_id' => (int) $usuario->getKey(), 'emisor' => trim($usuario->nombre.' '.$usuario->apellido)],
            'recorrido' => $recorrido];
        if ($base !== null) {
            $datos['blockchain_base'] = $base;
        }
        $path = 'certificados/'.$ambito.'/'.$uuid.'.pdf';
        try {
            // Generación costosa fuera de las transacciones que protegen los datos del producto.
            $pdf = $this->documento->generar($datos);
            if (! str_starts_with($pdf, '%PDF-') || ! Storage::disk('local')->put($path, $pdf)) {
                throw new \RuntimeException('No se pudo guardar el documento del certificado.');
            }
            $emision = DB::transaction(function () use ($capturar, $datos, $recorrido, $tipo, $emisor, $usuario, $entrada, $huella, $uuid, $codigo, $fecha, $ambito, $path) {
                $segunda = $capturar();
                if ($segunda instanceof Model) {
                    return $segunda;
                }
                [$actual, $vigente, $baseVigente] = $segunda;
                if ($recorrido !== $vigente || ($datos['blockchain_base'] ?? null) !== $baseVigente) {
                    throw ValidationException::withMessages(['certificado' => 'Los datos del producto cambiaron durante la emisión. Revise los antecedentes y vuelva a emitir.']);
                }
                $emision = new $tipo;
                $emision->forceFill([
                    $ambito === 'campo' ? 'loteid' : 'loteproduccionpedidoid' => $actual->getKey(),
                    $emisor => $usuario->getKey(), 'codigo_certificado' => $codigo,
                    $ambito === 'campo' ? 'resultado' : 'razon' => $entrada['resultado'],
                    'observaciones' => $entrada['observaciones'], 'recomendaciones' => $entrada['recomendaciones'],
                    $ambito === 'campo' ? 'fecha_certificacion' : 'fecha_evaluacion' => $fecha,
                    'emision_uuid' => $uuid, 'solicitud_id' => $entrada['solicitud_id'], 'solicitud_huella' => $huella,
                    'datos_emision' => $datos, 'archivo_path' => $path, 'formato_version' => CertificadoDocumentoService::VERSION,
                ])->save();
                if ($ambito === 'campo') {
                    $estado = EstadoLoteTipo::firstOrCreate(['nombre' => $entrada['resultado']], ['descripcion' => 'Resultado de certificación de campo']);
                    $actual->update(['estadolotetipoid' => $estado->getKey()]);
                    HistorialEstadoLote::create(['loteid' => $actual->getKey(), 'estadolotetipoid' => $estado->getKey(),
                        'fecha_cambio' => $fecha, 'usuarioid' => $usuario->getKey(),
                        'observaciones' => $entrada['resultado'].': '.$codigo.($entrada['observaciones'] ? ' — '.$entrada['observaciones'] : '')]);
                } elseif ($entrada['resultado'] === CertificacionLote::RAZON_NO_CONFORME) {
                    // La nueva evaluación cierra el lote; no borra almacenajes ni antecedentes anteriores.
                    $actual->update(['hora_fin' => now()]);
                }

                return $emision;
            }, 5);
        } catch (\Throwable $e) {
            $this->limpiarArchivoSinReferencia($tipo, $path);
            // Otro proceso pudo confirmar la misma solicitud después de nuestra captura.
            // Resolver fuera de la transacción abortada también cubre el índice único en PostgreSQL.
            if ($e instanceof \Illuminate\Database\QueryException && $entrada['solicitud_id']
                && in_array((string) $e->getCode(), ['23505', '23000'], true)) {
                $confirmada = $tipo::where($emisor, $usuario->getKey())->where('solicitud_id', $entrada['solicitud_id'])->first();
                if ($confirmada && hash_equals((string) $confirmada->solicitud_huella, $huella)) {
                    return $confirmada;
                }
            }
            throw $e;
        }
        if ($emision->archivo_path !== $path) {
            $this->limpiarArchivoSinReferencia($tipo, $path);
        } elseif ($ambito === 'campo') {
            // Conservar la integración existente sin alterar datos ni archivos históricos.
            try {
                app(CertificacionBlockchainService::class)->encolarSiCorresponde($emision);
            } catch (\Throwable $e) {
                report($e);
            }
        }

        return $emision->fresh();
    }

    private function bloquear(Model $lote, Usuario $usuario): Model
    {
        if (DB::getDriverName() === 'pgsql' && DB::transactionLevel() === 1) {
            DB::statement('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
        }
        if (DB::getDriverName() === 'pgsql') {
            // Serializar claves de solicitud del emisor sin bloquear referencias FK de las etapas.
            Usuario::whereKey($usuario->getKey())->lock('FOR NO KEY UPDATE')->firstOrFail();
        }
        if (DB::getDriverName() === 'sqlite') {
            $columna = $lote instanceof Lote ? 'nombre' : 'codigo_lote';
            DB::table($lote->getTable())->where($lote->getKeyName(), $lote->getKey())->update([$columna => DB::raw($columna)]);
        }

        return $lote->newQuery()->whereKey($lote->getKey())->lockForUpdate()->firstOrFail();
    }

    private function autorizar(string $ambito, Usuario $usuario, Model $lote): void
    {
        if ($ambito === 'campo') {
            abort_unless($usuario->can('certificaciones.create') && UsuarioRol::gestionaCampo($usuario), 403);
            if (! LoteAcceso::puedeGestionar($usuario, $lote)) {
                throw ValidationException::withMessages(['loteid' => 'No puede certificar un lote que no pertenece a su equipo.']);
            }
        } else {
            abort_unless($usuario->can('lote_produccion.update') && UsuarioRol::gestionaPlanta($usuario) && CertificadoAcceso::planta($usuario, $lote), 403);
        }
    }

    private function requisitos(string $ambito, Usuario $usuario, Model $lote): void
    {
        if ($ambito === 'campo') {
            $traza = app(LoteTrazabilidadService::class);
            $lote->load(['producciones', 'actividades.tipoActividad']);
            $primera = ! $lote->certificaciones()->exists();
            $valido = (! $primera || $traza->puedeCertificarCampo($lote, $usuario))
                && $lote->producciones->isNotEmpty() && $traza->actividadesPendientes($lote, false)->isEmpty()
                && $traza->actividadesCrecimientoCompletas($lote);
        } else {
            $valido = app(LoteProduccionTrazabilidadService::class)->transformacionCompleta($lote);
        }
        if (! $valido) {
            throw ValidationException::withMessages(['certificado' => 'Complete las actividades y requisitos del lote antes de emitir el certificado.']);
        }
    }

    private function limpiarArchivoSinReferencia(string $tipo, string $path): void
    {
        try {
            if (! $tipo::where('archivo_path', $path)->exists()) {
                Storage::disk('local')->delete($path);
            }
        } catch (\Throwable $e) {
            Log::warning('No se pudo comprobar un archivo nuevo de certificado; se conserva para revisión.', ['archivo' => $path]);
        }
    }
}
