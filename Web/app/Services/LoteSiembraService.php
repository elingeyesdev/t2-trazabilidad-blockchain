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

use Illuminate\Http\UploadedFile;

use Illuminate\Support\Facades\DB;

use Illuminate\Validation\ValidationException;



class LoteSiembraService

{

    public function __construct(

        private readonly LoteTrazabilidadService $trazabilidad,

        private readonly NotificacionUsuarioService $notificaciones,

        private readonly ActividadSecuenciaService $secuencia,

    ) {}



    public function asignar(Lote $lote, int $responsableId, ?int $asignadoPorId = null): Actividad

    {

        $tipo = $this->tipoSiembra();

        $faseActual = $this->trazabilidad->resolverFaseActual($lote);



        if ($this->trazabilidad->siembraCompletada($lote)) {

            throw ValidationException::withMessages([

                'siembra' => 'Este lote ya fue sembrado.',

            ]);

        }



        if ($this->trazabilidad->actividadSiembraPendiente($lote) !== null) {

            throw ValidationException::withMessages([

                'siembra' => 'Ya hay una siembra asignada pendiente de realizar.',

            ]);

        }



        if (! $this->trazabilidad->tipoActividadPermitidoEnFase($tipo->nombre, $faseActual)) {

            throw ValidationException::withMessages([

                'siembra' => 'El lote no está en fase de siembra.',

            ]);

        }



        $bloqueo = $this->trazabilidad->mensajeActividadNoPermitida($lote, $tipo->nombre);

        if ($bloqueo !== null) {

            throw ValidationException::withMessages(['siembra' => $bloqueo]);

        }



        $ahora = now();



        $actividad = DB::transaction(function () use ($lote, $tipo, $responsableId, $ahora) {

            $prioridadId = Prioridad::query()->orderBy('prioridadid')->value('prioridadid');

            if (! $prioridadId) {
                $prioridadId = Prioridad::firstOrCreate(['nombre' => 'Media'], ['nombre' => 'Media'])->prioridadid;
            }

            $actividad = Actividad::create([

                'loteid' => $lote->loteid,

                'usuarioid' => $responsableId,

                'descripcion' => $tipo->nombre ?? 'Siembra',

                'fechainicio' => $ahora,

                'fechafin' => null,

                'tipoactividadid' => $tipo->tipoactividadid,

                'prioridadid' => $prioridadId,

                'observaciones' => 'Siembra asignada desde trazabilidad del lote.',

            ]);

            $this->secuencia->asignarOrden($actividad);

            return $actividad;

        });



        if ($asignadoPorId !== null && (int) $asignadoPorId !== $responsableId) {

            $this->notificaciones->actividadAsignada($actividad);

        }



        return $actividad;

    }



    /**
     * Registra la siembra como completada con foto (actividad pendiente o hito directo del agricultor).
     */
    public function completarConEvidencia(Lote $lote, Usuario $usuario, UploadedFile $foto, ?string $observaciones = null, ?array $consumos = null): Actividad
    {
        $tipo = $this->tipoSiembra();
        $request = \Illuminate\Http\Request::create('/', 'POST', ['resultado' => $observaciones]);
        if ($consumos !== null) {
            $request->merge(['consumos' => $consumos]);
        }
        $request->files->set('evidencia_foto', $foto);
        $request->setUserResolver(fn () => $usuario);
        $provisional = new Actividad(['loteid' => $lote->loteid, 'usuarioid' => $usuario->usuarioid]);
        $provisional->setRelation('lote', $lote);

        return app(ActividadCierreService::class)->cerrar($request, $provisional, function () use ($lote, $tipo, $usuario) {
            $existente = Actividad::query()->where('loteid', $lote->loteid)
                ->where('tipoactividadid', $tipo->tipoactividadid)->orderBy('actividadid')->lockForUpdate()->first();
            if ($existente) {
                return $existente;
            }
            $prioridad = Prioridad::query()->orderBy('prioridadid')->value('prioridadid')
                ?? Prioridad::firstOrCreate(['nombre' => 'Media'])->prioridadid;
            $actividad = Actividad::create([
                'loteid' => $lote->loteid, 'usuarioid' => $usuario->usuarioid,
                'descripcion' => $tipo->nombre, 'tipoactividadid' => $tipo->tipoactividadid,
                'prioridadid' => $prioridad, 'fechainicio' => now(),
            ]);
            $this->secuencia->asignarOrden($actividad);
            return $actividad;
        });
    }
    private function tipoSiembra(): TipoActividad

    {

        $existente = TipoActividad::query()

            ->whereRaw('LOWER(TRIM(nombre)) LIKE ?', ['%siembra%'])

            ->orderBy('tipoactividadid')

            ->first();

        if ($existente) {

            return $existente;

        }

        return TipoActividad::updateOrCreate(

            ['nombre' => 'Siembra'],

            ['descripcion' => 'Siembra']

        );

    }

}

