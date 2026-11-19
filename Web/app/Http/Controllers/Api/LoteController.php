<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Lote;
use App\Models\Usuario;
use App\Http\Resources\Api\LoteConsultaResource;
use App\Support\ActividadPermisos;
use App\Support\LoteAcceso;
use App\Support\LoteTrazabilidadService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class LoteController extends Controller
{
    public function index(Request $request)
    {
        $filters = $request->validate([
            'q' => ['sometimes', 'string', 'max:100'],
            'insumosemillaid' => ['sometimes', 'integer', 'min:1'],
            'cultivoid' => ['sometimes', 'integer', 'min:1'],
            'estadolotetipoid' => ['sometimes', 'integer', 'min:1'],
            'usuarioid' => ['sometimes', 'integer', 'min:1'],
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'sort' => ['sometimes', 'string', Rule::in(['loteid', 'nombre', 'superficie', 'fechasiembra', 'fechacreacion', 'fechamodificacion'])],
            'direction' => ['sometimes', 'string', Rule::in(['asc', 'desc'])],
        ]);

        $query = Lote::query()->with($this->relacionesConsulta($request->user()));
        LoteAcceso::aplicarScopeVisibles($query, $request->user());

        if (filled($filters['q'] ?? null)) {
            $term = '%'.trim($filters['q']).'%';
            $query->where(function (Builder $builder) use ($term) {
                $builder->where('nombre', 'like', $term)
                    ->orWhere('ubicacion', 'like', $term)
                    ->orWhere('codigo_trazabilidad', 'like', $term);
            });
        }

        if (isset($filters['insumosemillaid'])) {
            $query->where('insumosemillaid', $filters['insumosemillaid']);
        } elseif (isset($filters['cultivoid'])) {
            $query->where('cultivoid', $filters['cultivoid']);
        }

        foreach (['estadolotetipoid', 'usuarioid'] as $field) {
            if (isset($filters[$field])) {
                $query->where($field, $filters[$field]);
            }
        }

        return LoteConsultaResource::collection(
            $query->orderBy($filters['sort'] ?? 'loteid', $filters['direction'] ?? 'desc')
                ->paginate($filters['per_page'] ?? 15)
                ->withQueryString()
        );
    }

    public function show(Request $request, $lote)
    {
        $lote = $this->consultaLotesVisibles($request->user())->findOrFail($lote);
        $lote->load($this->relacionesConsulta($request->user(), detalle: true));
        $historial = app(LoteTrazabilidadService::class)->buildEventos($lote);

        return (new LoteConsultaResource($lote))->withHistorial($historial);
    }

    private function consultaLotesVisibles(?Usuario $user): Builder
    {
        $query = Lote::query();
        LoteAcceso::aplicarScopeVisibles($query, $user);

        return $query;
    }

    /** @return array<string, mixed> */
    private function relacionesConsulta(?Usuario $user, bool $detalle = false): array
    {
        $relations = [
            'usuario:usuarioid,nombre,apellido',
            'cultivo:cultivoid,nombre,detalle',
            'estadoTipo:estadolotetipoid,nombre',
            'insumoSemilla:insumoid,nombre',
        ];

            if (! $detalle) {
                return $relations;
        }

            $relations['actividades'] = function ($relation) use ($user) {
                ActividadPermisos::aplicarScopeVisibles($relation->getQuery(), $user);
                $query = $relation->getQuery();
                $query->with([
                    'usuario:usuarioid,nombre,apellido',
                    'ejecutor:usuarioid,nombre,apellido',
                    'tipoActividad:tipoactividadid,nombre',
                    'prioridad:prioridadid,nombre',
                ])->orderBy('fechainicio')->orderBy('actividadid');
            };
            $relations['unidadSuperficie'] = fn ($relation) => $relation->select(['unidadmedidaid', 'nombre', 'abreviatura']);
            $relations['producciones'] = fn ($relation) => $relation->select([
                'produccionid', 'loteid', 'cantidad', 'unidadmedidaid', 'fechacosecha', 'imagenurl', 'destinoproduccionid',
            ]);

        return $relations;
    }

    /** Reuses web seed, stock, geography and history rules. */
    public function store(Request $request)
    {
        $this->prepararEscritura($request);
        $request->merge(['usuarioid' => $request->user()->usuarioid]);
        $lote = \Illuminate\Support\Facades\DB::transaction(
            fn () => app(\App\Http\Controllers\Web\LoteController::class)->store($request, true)
        );
        return (new LoteConsultaResource($lote->load($this->relacionesConsulta($request->user()))))
            ->response()->setStatusCode(201);
    }

    /** PUT and PATCH retain omitted fields, preserving the existing mobile contract. */
    public function update(Request $request, $lote)
    {
        $lote = Lote::query()->findOrFail($lote);
        abort_unless(LoteAcceso::puedeGestionar($request->user(), $lote), 403, 'No tienes acceso a este lote.');
        $this->prepararEscritura($request, true);
        $fields = ['nombre', 'ubicacion', 'superficie', 'insumosemillaid', 'cantidad_semilla_planificada', 'latitud', 'longitud'];
        $request->attributes->set('lote_campos_enviados', array_keys($request->only($fields)));
        $data = array_replace($lote->only($fields), $request->only($fields));
        if (array_intersect(['latitud', 'longitud'], $request->attributes->get('lote_campos_enviados'))) {
            $this->validarCoordenadas($data);
        }
        $request->replace($data + ['usuarioid' => $lote->usuarioid]);
        $lote = \Illuminate\Support\Facades\DB::transaction(
            fn () => app(\App\Http\Controllers\Web\LoteController::class)->update($request, $lote, true)
        );
        return new LoteConsultaResource($lote->load($this->relacionesConsulta($request->user())));
    }

    private function prepararEscritura(Request $request, bool $parcial = false): void
    {
        $request->headers->set('Accept', 'application/json');
        $rules = [];
        foreach (['usuarioid', 'cultivoid', 'actorid', 'estadolotetipoid', 'unidadsuperficieid', 'codigo_trazabilidad', 'fechasiembra', 'fechacreacion', 'fechamodificacion', 'imagenurl', 'organizacionid', 'role', 'insumosemallaid'] as $field) {
            $rules[$field] = ['missing'];
        }
        $rules['insumosemillaid'] = [$parcial ? 'sometimes' : 'required', 'required', 'integer', 'exists:insumo,insumoid'];
        $rules['superficie'] = [$parcial ? 'sometimes' : 'required', 'required', 'numeric', 'min:0.01'];
        $rules['latitud'] = ['sometimes', 'nullable', 'numeric', 'between:-90,90'];
        $rules['longitud'] = ['sometimes', 'nullable', 'numeric', 'between:-180,180'];
        $request->validate($rules, ['missing' => 'El campo :attribute se establece en el servidor.', 'required' => 'El campo :attribute es obligatorio.']);
        if (! $parcial) {
            $this->validarCoordenadas($request->only(['latitud', 'longitud']));
        }
        if ($request->filled('insumosemillaid')) {
            $ids = \App\Support\AlmacenAcceso::idsVisibles($request->user());
            $insumo = \App\Models\Insumo::with('almacen')->find($request->input('insumosemillaid'));
            $visible = $insumo && ($insumo->almacenid === null || ($insumo->almacen
                && (\App\Support\AlmacenAmbito::resolverAmbito($insumo->almacen) === \App\Support\AlmacenAmbito::AGRICOLA
                    ? \App\Support\CampoAccess::puedeVerAlmacen($request->user(), $insumo->almacen)
                    : in_array($insumo->almacenid, $ids, true))));
            if (! $visible) {
                throw \Illuminate\Validation\ValidationException::withMessages(['insumosemillaid' => 'Seleccione una semilla de su ámbito autorizado.']);
            }
        }
    }

    private function validarCoordenadas(array $data): void
    {
        if (($data['latitud'] ?? null) === null xor ($data['longitud'] ?? null) === null) {
            throw \Illuminate\Validation\ValidationException::withMessages([
                'latitud' => 'Indique ambas coordenadas o deje ambas vacías.',
                'longitud' => 'Indique ambas coordenadas o deje ambas vacías.',
            ]);
        }
    }
    public function destroy(Request $request, $lote)
    {
        $lote = $lote instanceof Lote ? $lote : Lote::query()->findOrFail($lote);
        abort_unless(LoteAcceso::puedeGestionar($request->user(), $lote), 403, 'No tienes acceso a este lote.');

        $lote->delete();

        return response()->json(['message' => 'Eliminado correctamente']);
    }
}
