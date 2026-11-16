<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Actividad;
use App\Models\Lote;
use App\Http\Resources\Api\ActividadConsultaResource;
use App\Support\ActividadPermisos;
use App\Support\LoteAcceso;
use App\Support\UsuarioRol;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class ActividadController extends Controller
{
    public function index(Request $request)
    {
        $filters = $request->validate($this->reglasConsulta(incluirLote: true));
        $query = $this->consultaActividadesVisibles($request, $filters);

        return ActividadConsultaResource::collection(
            $query->orderBy($filters['sort'] ?? 'actividadid', $filters['direction'] ?? 'desc')
                ->paginate($filters['per_page'] ?? 15)
                ->withQueryString()
        );
    }

    public function porLote(Request $request, $lote)
    {
        $filters = $request->validate($this->reglasConsulta(incluirLote: false));
        $loteQuery = Lote::query();
        LoteAcceso::aplicarScopeVisibles($loteQuery, $request->user());
        $lote = $loteQuery->findOrFail($lote);

        $query = $lote->actividades()->with($this->relacionesActividad());
        ActividadPermisos::aplicarScopeVisibles($query->getQuery(), $request->user());
        $query = $this->aplicarFiltros($query->getQuery(), $filters);

        $sort = $filters['sort'] ?? 'actividadid';
        $direction = $filters['direction'] ?? 'desc';
        $query->orderBy($sort, $direction);
        if ($sort !== 'actividadid') {
            $query->orderBy('actividadid', $direction);
        }

        return ActividadConsultaResource::collection(
            $query->paginate($filters['per_page'] ?? 15)
                ->withQueryString()
        );
    }

    public function showEnLote(Request $request, $lote, $actividad)
    {
        $loteQuery = Lote::query();
        LoteAcceso::aplicarScopeVisibles($loteQuery, $request->user());
        $lote = $loteQuery->findOrFail($lote);

        $query = $lote->actividades()->with($this->relacionesActividad());
        ActividadPermisos::aplicarScopeVisibles($query->getQuery(), $request->user());
        $actividad = $query->whereKey($actividad)->firstOrFail();

        return new ActividadConsultaResource($actividad);
    }

    public function show(Request $request, $actividad)
    {
        $query = Actividad::query()->with($this->relacionesActividad());
        ActividadPermisos::aplicarScopeVisibles($query, $request->user());
        $actividad = $query->findOrFail($actividad);

        return new ActividadConsultaResource($actividad);
    }

    /** @return array<string, array<int, string>|string> */
    private function reglasConsulta(bool $incluirLote): array
    {
        $rules = [
            'q' => ['sometimes', 'string', 'max:100'],
            'estado' => ['sometimes', 'string', Rule::in(['pendiente', 'completada'])],
            'tipoactividadid' => ['sometimes', 'integer', 'min:1'],
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'sort' => ['sometimes', 'string', Rule::in(['actividadid', 'descripcion', 'fechainicio', 'fecha_planificada', 'fechafin'])],
            'direction' => ['sometimes', 'string', Rule::in(['asc', 'desc'])],
        ];

        if ($incluirLote) {
            $rules['loteid'] = ['sometimes', 'integer', 'min:1'];
        } else {
            $rules['loteid'] = ['prohibited'];
        }

        return $rules;
    }

    /** @param array<string, mixed> $filters
     *  @return Builder<Actividad>
     */
    private function consultaActividadesVisibles(Request $request, array $filters): Builder
    {
        $query = Actividad::query()->with($this->relacionesActividad());
        ActividadPermisos::aplicarScopeVisibles($query, $request->user());

        return $this->aplicarFiltros($query, $filters);
    }

    /** @param array<string, mixed> $filters
     *  @return Builder<Actividad>
     */
    private function aplicarFiltros(Builder $query, array $filters): Builder
    {
        if (filled($filters['q'] ?? null)) {
            $term = '%'.trim($filters['q']).'%';
            $query->where(function (Builder $builder) use ($term) {
                $builder->where('descripcion', 'like', $term)
                    ->orWhereHas('lote', fn (Builder $lote) => $lote->where('nombre', 'like', $term))
                    ->orWhereHas('tipoActividad', fn (Builder $tipo) => $tipo->where('nombre', 'like', $term))
                    ->orWhereHas('usuario', fn (Builder $usuario) => $usuario->where('nombre', 'like', $term));
            });
        }

        if (($filters['estado'] ?? null) === 'pendiente') {
            $query->whereNull('fechafin');
        } elseif (($filters['estado'] ?? null) === 'completada') {
            $query->whereNotNull('fechafin');
        }

        foreach (['loteid', 'tipoactividadid'] as $field) {
            if (isset($filters[$field])) {
                $query->where($field, $filters[$field]);
            }
        }

        return $query;
    }

    /** @return array<string, string> */
    private function relacionesActividad(): array
    {
        return [
            'lote:loteid,nombre,cultivoid,estadolotetipoid,usuarioid',
            'lote.cultivo:cultivoid,nombre',
            'lote.estadoTipo:estadolotetipoid,nombre',
            'usuario:usuarioid,nombre,apellido',
            'ejecutor:usuarioid,nombre,apellido',
            'tipoActividad:tipoactividadid,nombre',
            'prioridad:prioridadid,nombre',
        ];
    }

    public function store(Request $request)
    {
        $request->headers->set('Accept', 'application/json');
        abort_unless(UsuarioRol::gestionaCampo($request->user()) && UsuarioRol::puedeOperar($request->user()), 403, 'Solo el jefe agrícola puede asignar actividades.');
        $request->validate([
            'loteid' => 'required|integer|exists:lote,loteid',
            'usuarioid' => 'required|integer|exists:usuario,usuarioid',
            'fechafin' => 'missing',
            'completar' => 'missing',
            'usuarioid_ejecutor' => 'missing',
            'orden_secuencia' => 'missing',
            'evidencia_foto_path' => 'missing',
            'detalle_json' => 'missing',
        ], ['missing' => 'El campo :attribute no puede establecerse al asignar una actividad.']);
        $lote = Lote::findOrFail($request->integer('loteid'));
        abort_unless(LoteAcceso::puedeGestionar($request->user(), $lote), 403, 'No tienes acceso a este lote.');
        $this->validarResponsable($request);
        $actividad = \Illuminate\Support\Facades\DB::transaction(function () use ($request, $lote) {
            Lote::query()->whereKey($lote->loteid)->lockForUpdate()->firstOrFail();

            return app(\App\Http\Controllers\Web\ActividadController::class)->store($request, true);
        });
        return (new ActividadConsultaResource($actividad->load($this->relacionesActividad())))
            ->response()->setStatusCode(201);
    }

    private function validarResponsable(Request $request): void
    {
        $actor = $request->user();
        $id = $request->integer('usuarioid');
        $usuario = \App\Models\Usuario::find($id);
        $permitido = $usuario && $usuario->activo && UsuarioRol::puedeOperar($actor)
            && (($id === (int) $actor->usuarioid && UsuarioRol::gestionaCampo($actor))
                || (UsuarioRol::esJefeAgricultor($actor)
                    && UsuarioRol::esResponsableActividadPermitido($usuario)
                    && in_array($id, UsuarioRol::idsEmpleadosOperativosDeJefeAgricultor($actor), true)));
        if (! $permitido) {
            throw \Illuminate\Validation\ValidationException::withMessages(['usuarioid' => 'Seleccione un trabajador activo de su equipo.']);
        }
    }
    public function update(Request $request, $actividad)
    {
        $actividad = $actividad instanceof Actividad
            ? $actividad
            : Actividad::query()->findOrFail($actividad);

        abort_unless(
            ActividadPermisos::puedeAcceder($request->user(), $actividad),
            403,
            'No tienes acceso a esta actividad.'
        );
        abort_if($actividad->fechafin !== null, 409, 'El cierre confirmado de esta actividad no puede modificarse.');

        $data = $request->validate([
            'loteid' => 'sometimes|exists:lote,loteid',
            'usuarioid' => 'sometimes|exists:usuario,usuarioid',
            'descripcion' => 'sometimes|string|max:200',
            'fechainicio' => 'nullable|date',
            'fecha_planificada' => 'nullable|date',
            'fechafin' => 'missing',
            'tipoactividadid' => 'sometimes|exists:tipoactividad,tipoactividadid',
            'prioridadid' => 'sometimes|exists:prioridad,prioridadid',
            'observaciones' => 'nullable|string|max:250',
        ]);

        $user = $request->user();

        if (array_key_exists('loteid', $data) && (int) $data['loteid'] !== (int) $actividad->loteid) {
            throw \Illuminate\Validation\ValidationException::withMessages(['loteid' => 'No se puede trasladar una actividad a otro lote.']);
        }
        if (array_key_exists('usuarioid', $data)) {
            abort_unless(UsuarioRol::gestionaCampo($user) && LoteAcceso::puedeGestionar($user, $actividad->lote), 403, 'No puede reasignar esta actividad.');
            $this->validarResponsable($request);
        }
        if (isset($data['loteid'])) {
            $lote = Lote::query()->findOrFail((int) $data['loteid']);
            $permitido = Lote::query()
                ->where('loteid', $lote->loteid)
                ->tap(fn ($q) => LoteAcceso::aplicarScopeOperativoActividad($q, $user))
                ->exists();
            abort_unless($permitido, 403, 'No tienes acceso a este lote.');
        }

        if (UsuarioRol::debeAcotarPorAsignacion($user)) {
            unset($data['usuarioid']);
        }

        if (array_key_exists('fechafin', $data) && $data['fechafin'] !== null) {
            abort_unless(
                ActividadPermisos::puedeMarcarCompletada($user, $actividad),
                403,
                'No puede completar esta actividad.'
            );
            app(\App\Support\ActividadSecuenciaService::class)->asegurarEnTurnoParaCompletar($actividad);
        }

        $actividad->update($data);

        return new ActividadConsultaResource($actividad->fresh()->load($this->relacionesActividad()));
    }

    public function destroy(Request $request, $actividad)
    {
        $actividad = $actividad instanceof Actividad
            ? $actividad
            : Actividad::query()->findOrFail($actividad);

        $actividad->loadMissing('lote');

        abort_unless(
            ActividadPermisos::puedeAcceder($request->user(), $actividad)
            && $actividad->lote
            && LoteAcceso::puedeGestionar($request->user(), $actividad->lote),
            403,
            'No tienes permiso para eliminar esta actividad.'
        );
        abort_if($actividad->fechafin !== null, 409, 'No se puede eliminar una actividad con cierre confirmado.');

        $actividad->delete();

        return response()->json(['message' => 'Eliminado correctamente']);
    }
}
