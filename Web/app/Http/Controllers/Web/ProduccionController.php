<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\Lote;
use App\Models\Produccion;
use App\Services\CosechaPresentacionService;
use App\Services\CosechaRegistroService;
use App\Services\PlanificacionCosechaService;
use App\Support\LoteAcceso;
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Http\Request;

class ProduccionController extends Controller
{
    public function __construct(private readonly CosechaRegistroService $registro) {}

    public function index(Request $request)
    {
        $filtros = $request->validate([
            'loteid' => 'sometimes|nullable|integer|min:1', 'buscar' => 'nullable|string|max:150',
            'fecha_desde' => 'nullable|date_format:Y-m-d', 'fecha_hasta' => 'nullable|date_format:Y-m-d',
        ]);
        $query = $this->registro->consulta($request->user());
        $loteFiltroSeleccionado = $request->filled('loteid')
            ? $this->registro->loteVisible($request->user(), (int) $filtros['loteid']) : null;
        if ($loteFiltroSeleccionado) {
            $query->where('loteid', $loteFiltroSeleccionado->loteid);
        }
        foreach (['fecha_desde' => '>=', 'fecha_hasta' => '<='] as $campo => $operador) {
            if ($request->filled($campo)) {
                $query->whereDate('fechacosecha', $operador, $filtros[$campo]);
            }
        }
        if ($request->filled('buscar')) {
            $buscar = '%'.trim($filtros['buscar']).'%';
            $query->where(fn ($q) => $q->whereHas('lote', fn ($l) => $l->where('nombre', 'like', $buscar))
                ->orWhereHas('lote.insumoSemilla', fn ($i) => $i->where('nombre', 'like', $buscar))
                ->orWhere('observaciones', 'like', $buscar));
        }
        $filas = (clone $query)->get(['loteid', 'cantidad_base']);
        $kg = BigDecimal::zero();
        $conEquivalencia = 0;
        foreach ($filas as $fila) {
            if ($fila->cantidad_base !== null) {
                $kg = $kg->plus($fila->cantidad_base);
                $conEquivalencia++;
            }
        }
        $stats = ['total' => $filas->count(), 'lotes' => $filas->pluck('loteid')->unique()->count(),
            'kg_total' => (string) $kg, 'promedio' => $conEquivalencia ? (string) $kg->dividedBy($conEquivalencia, 6, RoundingMode::HALF_UP) : '0'];
        $producciones = $query->with(['lote.usuario', 'lote.insumoSemilla', 'lote.cultivo', 'destino', 'unidadMedida', 'almacenamientos.almacen'])
            ->orderByDesc('fechacosecha')->orderByDesc('produccionid')->paginate(15)->withQueryString();
        $loteIdsCosechadosFilter = $this->registro->consulta($request->user())->distinct()->pluck('loteid');

        return view('producciones.index', compact('producciones', 'stats', 'loteIdsCosechadosFilter', 'loteFiltroSeleccionado'));
    }

    public function create(Request $request)
    {
        $request->validate(['loteid' => 'sometimes|nullable|integer|min:1']);
        $loteidParam = $request->integer('loteid') ?: null;
        $preseleccion = $loteidParam ?: (old('loteid') ? (int) old('loteid') : null);
        $loteActivo = $preseleccion ? $this->registro->loteVisible($request->user(), $preseleccion) : null;
        if ($loteActivo) {
            abort_unless($this->registro->puedeRegistrar($request->user(), $loteActivo), 403, 'No tienes permiso o el lote no está listo para cosecha.');
            $loteActivo->load(['usuario', 'cultivo', 'insumoSemilla', 'estadoTipo', 'catalogoTamanoConteo.tipoEmpaque']);
        }
        $query = Lote::with(['usuario', 'cultivo', 'estadoTipo', 'actividades.tipoActividad']);
        LoteAcceso::aplicarScopeVisibles($query, $request->user());
        $lotes = $query->orderBy('nombre')->get()->filter(fn (Lote $lote) => $this->registro->puedeRegistrar($request->user(), $lote))->values();
        $unidades = CosechaRegistroService::unidades();
        $lotePreseleccionado = $loteActivo?->loteid;
        $lotePreseleccionadoLabel = $loteActivo?->nombre;
        $usarLoteFijo = $loteActivo !== null && ($loteidParam || $lotes->count() === 1);
        $estimacionLoteInicial = $loteActivo ? app(PlanificacionCosechaService::class)->estimacionUiDesdeLote($loteActivo, soloLectura: true) : null;
        $returnUrl = $this->validReturnUrl($request);

        return view('producciones.create', compact('lotes', 'unidades', 'lotePreseleccionado', 'lotePreseleccionadoLabel', 'returnUrl', 'estimacionLoteInicial', 'loteActivo', 'usarLoteFijo', 'loteidParam'));
    }

    public function configuracion(Request $request)
    {
        $data = $request->validate(['loteid' => 'required|integer|min:1']);

        return response()->json($this->registro->configuracion($request->user(), (int) $data['loteid']));
    }

    public function vistaPrevia(Request $request)
    {
        return response()->json($this->registro->vistaPrevia($request));
    }

    public function store(Request $request)
    {
        $produccion = $this->registro->registrar($request);

        return redirect($this->validReturnUrl($request) ?? route('producciones.show', $produccion))
            ->with('success', 'Cosecha registrada. Certifique el lote antes de enviarlo al almacén.');
    }

    public function show(Request $request, Produccion $produccion)
    {
        $produccion = $this->registro->detalle($request->user(), (int) $produccion->produccionid);
        $presentacion = app(CosechaPresentacionService::class)->paraProduccion($produccion);

        return view('producciones.show', compact('produccion', 'presentacion'));
    }

    public function edit(Request $request, Produccion $produccion)
    {
        $this->registro->detalle($request->user(), (int) $produccion->produccionid);

        return redirect()->route('producciones.show', $produccion)->with('info', 'Las cosechas registradas son de solo lectura.');
    }

    public function update(Request $request, Produccion $produccion)
    {
        return $this->edit($request, $produccion);
    }

    public function destroy(Request $request, Produccion $produccion)
    {
        return $this->edit($request, $produccion);
    }

    private function validReturnUrl(Request $request): ?string
    {
        $return = $request->input('return');
        if (! is_string($return) || str_contains($return, '\\')) {
            return null;
        }
        if (str_starts_with($return, '/') && ! str_starts_with($return, '//')) {
            return $return;
        }

        return str_starts_with($return, $request->getSchemeAndHttpHost().'/') ? $return : null;
    }
}
