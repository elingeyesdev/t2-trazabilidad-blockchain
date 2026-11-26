<?php

namespace App\Services;

use App\Models\Actividad;
use App\Models\Lote;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use App\Models\Usuario;
use App\Support\ActividadSecuenciaService;
use App\Support\LoteTrazabilidadService;
use App\Support\UsuarioRol;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class LoteInicioService
{
    /** El formulario conserva su identificador al reintentar, incluso tras consumir stock. */
    public function registrar(Request $request, callable $crear): Lote
    {
        $request->validate(['solicitud_registro_id' => 'required|uuid']);
        $entrada = $request->except(['_token', '_method', 'solicitud_registro_id', 'imagen']);
        ksort($entrada);
        $entrada['imagen_sha256'] = $request->hasFile('imagen') ? hash_file('sha256', $request->file('imagen')->getRealPath()) : null;
        $huella = hash('sha256', json_encode($entrada, JSON_THROW_ON_ERROR));

        return DB::transaction(function () use ($request, $crear, $huella) {
            $uid = $request->user()->usuarioid;
            if (DB::getDriverName() === 'sqlite') {
                DB::table('usuario')->where('usuarioid', $uid)->update(['activo' => DB::raw('activo')]);
            }
            Usuario::whereKey($uid)->lockForUpdate()->firstOrFail();
            $anterior = Lote::where('solicitud_registro_id', $request->input('solicitud_registro_id'))->first();
            if ($anterior) {
                abort_unless((int) $anterior->usuarioid === (int) $uid
                    && hash_equals((string) $anterior->solicitud_registro_huella, $huella), 409, 'El reintento contiene datos diferentes.');

                return $anterior;
            }
            $lote = $crear();
            $lote->forceFill(['solicitud_registro_id' => $request->input('solicitud_registro_id'), 'solicitud_registro_huella' => $huella])->save();

            return $lote;
        }, 5);
    }

    public function validarAgricultor(Usuario $jefe, int $usuarioid): void
    {
        if (! UsuarioRol::gestionaCampo($jefe) || ! UsuarioRol::esResponsableActividadPermitido(Usuario::find($usuarioid))
            || ! in_array($usuarioid, UsuarioRol::idsEmpleadosOperativosDeJefeAgricultor($jefe), true)) {
            throw ValidationException::withMessages(['agricultor_inicial_usuarioid' => 'Seleccione un agricultor activo y aprobado de su equipo.']);
        }
    }

    /** Se invoca dentro de la transacción que crea el lote. */
    public function inicializar(Lote $lote, Usuario $jefe): void
    {
        $this->validarAgricultor($jefe, (int) $lote->agricultor_inicial_usuarioid);
        if (! $lote->preparacion_requerida) {
            app(LoteSiembraService::class)->asignar($lote, $lote->agricultor_inicial_usuarioid, $jefe->usuarioid);

            return;
        }
        $tipo = TipoActividad::firstOrCreate(['nombre' => 'Preparación del terreno'], ['descripcion' => 'Preparación del terreno antes de la siembra.']);
        $prioridad = Prioridad::firstOrCreate(['nombre' => 'Media']);
        $actividad = Actividad::create([
            'loteid' => $lote->loteid, 'usuarioid' => $lote->agricultor_inicial_usuarioid,
            'tipoactividadid' => $tipo->tipoactividadid, 'prioridadid' => $prioridad->prioridadid,
            'descripcion' => 'Preparación del terreno', 'fechainicio' => now(),
            'observaciones' => 'Preparación requerida al registrar el lote.',
        ]);
        app(ActividadSecuenciaService::class)->asignarOrden($actividad);
        app(NotificacionUsuarioService::class)->actividadAsignada($actividad);
    }

    public function continuarTrasPreparacion(Actividad $actividad): void
    {
        $lote = $actividad->lote->fresh();
        $trazabilidad = app(LoteTrazabilidadService::class);
        if ($lote->preparacion_requerida !== true || $actividad->fechafin === null
            || ! $trazabilidad->esPreparacion($actividad->tipoActividad?->nombre)
            || $trazabilidad->siembraCompletada($lote) || $trazabilidad->actividadSiembraPendiente($lote)) {
            return;
        }
        // Si se reasignó la preparación, el ejecutor asignado continúa con la siembra.
        app(LoteSiembraService::class)->asignar($lote, (int) $actividad->usuarioid, (int) $lote->usuarioid);
    }
}
