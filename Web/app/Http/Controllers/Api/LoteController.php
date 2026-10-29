<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Lote;
use App\Models\Usuario;
use App\Http\Resources\Api\ActividadConsultaResource;
use App\Http\Resources\Api\LoteConsultaResource;
use App\Support\ActividadPermisos;
use App\Support\LoteAcceso;
use App\Support\LoteCultivoResolver;
use App\Support\LoteDefaults;
use App\Support\LoteTrazabilidadService;
use App\Support\UbicacionGpsParser;
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

    public function store(Request $request)
    {
        $data = $request->validate([
            'usuarioid' => 'required|exists:usuario,usuarioid',
            'nombre' => 'required|string|max:100',
            'ubicacion' => 'nullable|string|max:200',
            'superficie' => 'required|numeric|min:0.01',
            'insumosemallaid' => 'nullable|exists:insumo,insumoid',
            'cantidad_semilla_planificada' => 'nullable|numeric|min:0',
            'latitud' => 'nullable|numeric|between:-90,90',
            'longitud' => 'nullable|numeric|between:-180,180',
            'imagen' => 'nullable|image|max:2048',
        ]);

        $data['cultivoid'] = LoteCultivoResolver::resolver($data['insumosemallaid'] ?? null);

        $data['ubicacion'] = UbicacionGpsParser::normalizarUbicacionLote(
            $data['ubicacion'] ?? null,
            isset($data['latitud']) ? (float) $data['latitud'] : null,
            isset($data['longitud']) ? (float) $data['longitud'] : null
        );

        if ($request->hasFile('imagen')) {
            try {
                $file = $request->file('imagen');
                $filename = 'lote_' . uniqid() . '.' . $file->getClientOriginalExtension();
                $supabase = new \App\Services\SupabaseStorage();
                $response = $supabase->upload($filename, file_get_contents($file), $file->getMimeType());
                if ($response->successful()) {
                    $data['imagenurl'] = $supabase->getPublicUrl($filename);
                }
            } catch (\Exception $e) {
                \Illuminate\Support\Facades\Log::error('Supabase upload error: ' . $e->getMessage());
            }
        }

        unset($data['imagen']);
        $data = LoteDefaults::enrich($data, true);
        $lote = Lote::create($data);
        LoteDefaults::registrarHistorialInicial($lote);

        return response()->json(
            $lote->load(['usuario', 'cultivo', 'estadoTipo', 'insumoSemilla'])
                ->makeVisible(['usuario', 'cultivo', 'estadoTipo', 'insumoSemilla']),
            201
        );
    }

    public function update(Request $request, $lote)
    {
        $lote = $lote instanceof Lote ? $lote : Lote::query()->findOrFail($lote);
        abort_unless(LoteAcceso::puedeGestionar($request->user(), $lote), 403, 'No tienes acceso a este lote.');

        $data = $request->validate([
            'usuarioid' => 'sometimes|exists:usuario,usuarioid',
            'nombre' => 'sometimes|string|max:100',
            'ubicacion' => 'nullable|string|max:200',
            'superficie' => 'sometimes|numeric|min:0.01',
            'insumosemallaid' => 'nullable|exists:insumo,insumoid',
            'cantidad_semilla_planificada' => 'nullable|numeric|min:0',
            'latitud' => 'nullable|numeric|between:-90,90',
            'longitud' => 'nullable|numeric|between:-180,180',
        ]);

        if (isset($data['insumosemallaid'])) {
            $data['cultivoid'] = LoteCultivoResolver::resolver($data['insumosemallaid'] ?? null);
        }

        $data = LoteDefaults::enrich($data, false);
        $lote->update($data);

        return response()->json(
            $lote->load(['usuario', 'cultivo', 'estadoTipo', 'insumoSemilla'])
                ->makeVisible(['usuario', 'cultivo', 'estadoTipo', 'insumoSemilla'])
        );
    }

    public function destroy(Request $request, $lote)
    {
        $lote = $lote instanceof Lote ? $lote : Lote::query()->findOrFail($lote);
        abort_unless(LoteAcceso::puedeGestionar($request->user(), $lote), 403, 'No tienes acceso a este lote.');

        $lote->delete();

        return response()->json(['message' => 'Eliminado correctamente']);
    }
}
