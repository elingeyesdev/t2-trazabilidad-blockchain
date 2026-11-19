<?php

namespace App\Services;

use App\Models\CatalogoTamanoConteo;
use App\Models\DestinoProduccion;
use App\Models\HistorialEstadoLote;
use App\Models\Lote;
use App\Models\Produccion;
use App\Models\TipoEmpaque;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Support\CosechaDecimal;
use App\Support\EstadoLoteCatalogo;
use App\Support\EvidenciaFoto;
use App\Support\LoteAcceso;
use App\Support\LoteTrazabilidadService;
use App\Support\PedidoCatalogo;
use App\Support\UsuarioRol;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/** Single authorization, conversion and persistence boundary for web and mobile. */
class CosechaRegistroService
{
    public function __construct(
        private readonly LoteTrazabilidadService $trazabilidad,
        private readonly CosechaPresentacionService $presentacion,
    ) {}

    public function consulta(Usuario $user): Builder
    {
        return Produccion::query()->whereHas('lote', function (Builder $query) use ($user) {
            LoteAcceso::aplicarScopeVisibles($query, $user);
        });
    }

    public function loteVisible(Usuario $user, int $id, bool $bloquear = false): Lote
    {
        $query = Lote::query();
        LoteAcceso::aplicarScopeVisibles($query, $user);

        return ($bloquear ? $query->lockForUpdate() : $query)->findOrFail($id);
    }

    public function detalle(Usuario $user, int $id, ?int $loteId = null): Produccion
    {
        $query = $this->consulta($user);
        if ($loteId !== null) {
            $this->loteVisible($user, $loteId);
            $query->where('loteid', $loteId);
        }

        return $query->with(['lote.usuario', 'lote.insumoSemilla', 'lote.cultivo', 'destino', 'unidadMedida', 'almacenamientos.almacen'])->findOrFail($id);
    }

    public function puedeRegistrar(Usuario $user, Lote $lote): bool
    {
        return UsuarioRol::puedeOperar($user) && $user->can('lotes.view')
            && LoteAcceso::puedeVer($user, $lote)
            && $this->trazabilidad->puedeUsuarioRegistrarCosecha($lote, $user);
    }

    /** Read-only: never synchronizes or creates catalog defaults during a harvest request. */
    public function presentaciones(Lote $lote): Collection
    {
        $ids = $lote->insumosemillaid
            ? PedidoCatalogo::insumoIdsRelacionadosParaCalibres((int) $lote->insumosemillaid)
            : [];

        return CatalogoTamanoConteo::query()->with('tipoEmpaque')
            ->whereIn('insumoid', $ids)->where('activo', true)
            ->whereHas('tipoEmpaque', fn (Builder $query) => $query->where('activo', true))
            ->orderBy('nombre')->orderBy('catalogotamanoconteoid')->get();
    }

    public function configuracion(Usuario $user, int $loteId): array
    {
        $lote = $this->loteVisible($user, $loteId);
        $calibres = $this->presentaciones($lote);

        return [
            'predeterminada_id' => $calibres->contains('catalogotamanoconteoid', $lote->catalogotamanoconteoid) ? $lote->catalogotamanoconteoid : null,
            'presentaciones' => $calibres->map(fn (CatalogoTamanoConteo $c) => [
                'catalogotamanoconteoid' => (int) $c->catalogotamanoconteoid,
                'nombre' => $c->nombre,
                'peso_promedio_kg' => (string) $c->peso_promedio_kg,
                'conteo_por_empaque' => (int) $c->conteo_por_empaque,
                'empaque' => CosechaPresentacionService::tipoEmpaqueParaCosechaEnCampo($c->tipoEmpaque->nombre),
            ])->values()->all(),
        ];
    }

    public static function unidades(): Collection
    {
        return UnidadMedida::query()->where('categoria', 'peso')->get()
            ->filter(fn (UnidadMedida $u) => CosechaDecimal::factorUnidad($u) !== null)->values();
    }

    private function entrada(Request $request, bool $conFoto): array
    {
        // Compatibility for the old API field: it always means kg, never the selected unit.
        if ($request->exists('cantidadkg')) {
            if ($request->exists('cantidad')) {
                throw ValidationException::withMessages(['cantidadkg' => 'Envía cantidad o cantidadkg, no ambos campos.']);
            }
            $kg = $request->filled('unidadmedidaid') ? UnidadMedida::find($request->input('unidadmedidaid'))
                : self::unidades()->first(fn (UnidadMedida $u) => CosechaDecimal::factorUnidad($u) === '1');
            if (! $kg || CosechaDecimal::factorUnidad($kg) !== '1') {
                throw ValidationException::withMessages(['unidadmedidaid' => 'cantidadkg solo admite la unidad kilogramo configurada.']);
            }
            $request->merge(['cantidad' => $request->input('cantidadkg'), 'unidadmedidaid' => $kg->unidadmedidaid]);
        }
        $reglas = [
            'loteid' => 'required|integer|min:1',
            'cantidad' => ['required', function ($campo, $valor, $fallar) {
                try {
                    CosechaDecimal::cantidad($valor);
                } catch (ValidationException $e) {
                    $fallar($e->errors()['cantidad'][0]);
                }
            }],
            'unidadmedidaid' => 'required|integer|min:1',
            'catalogotamanoconteoid' => 'sometimes|required|integer|min:1',
            'fechacosecha' => 'sometimes|required|date_format:Y-m-d',
            'observaciones' => 'nullable|string|max:5000',
        ];
        foreach (['cantidad_base', 'cantidad_unidades', 'cantidad_empaques', 'presentacion_cosecha', 'factor', 'factor_conversion', 'peso_promedio_kg', 'conteo_por_empaque', 'equivalencia', 'usuarioid', 'propietario', 'imagenurl', 'destinoproduccionid', 'almacendestinoid'] as $campo) {
            $reglas[$campo] = 'missing';
        }
        if ($conFoto) {
            $reglas['evidencia_foto'] = 'required|file|image|mimes:jpeg,jpg,png,webp|max:5120';
        }

        return $request->validate($reglas, [
            'required' => 'El campo :attribute es obligatorio.',
            'integer' => 'Selecciona un identificador válido para :attribute.',
            'min' => 'Selecciona un identificador válido para :attribute.',
            'date_format' => 'La fecha de cosecha debe ser una fecha válida en formato AAAA-MM-DD.',
            'missing' => 'El campo :attribute lo calcula o establece el servidor; no debe enviarse.',
            'evidencia_foto.required' => 'Debe subir una foto de la cosecha realizada.',
            'evidencia_foto.image' => 'El archivo debe ser una imagen válida.',
            'evidencia_foto.mimes' => 'La foto debe ser JPG, PNG o WebP.',
            'evidencia_foto.max' => 'La imagen no puede superar 5 MB.',
            'observaciones.max' => 'Las observaciones no pueden superar 5000 caracteres.',
        ], ['loteid' => 'lote', 'unidadmedidaid' => 'unidad', 'catalogotamanoconteoid' => 'presentación', 'fechacosecha' => 'fecha de cosecha']);
    }

    private function calcular(Lote $lote, array $data, bool $bloquear): array
    {
        $id = $data['catalogotamanoconteoid'] ?? $lote->catalogotamanoconteoid;
        // Use the same related-product rule as the existing caliber catalog.
        $permitidas = $this->presentaciones($lote)->pluck('catalogotamanoconteoid')->all();
        $query = CatalogoTamanoConteo::query()->whereIn('catalogotamanoconteoid', $permitidas)->whereKey($id);
        $calibre = ($bloquear ? $query->lockForUpdate() : $query)->first();
        $insumosPermitidos = $lote->insumosemillaid ? PedidoCatalogo::insumoIdsRelacionadosParaCalibres((int) $lote->insumosemillaid) : [];
        if (! $calibre || ! $calibre->activo || ! in_array((int) $calibre->insumoid, $insumosPermitidos, true)) {
            throw ValidationException::withMessages(['catalogotamanoconteoid' => 'Selecciona una presentación activa y aplicable al producto de este lote.']);
        }
        $tipoQuery = TipoEmpaque::query()->whereKey($calibre->tipoempaqueid);
        $tipo = ($bloquear ? $tipoQuery->lockForUpdate() : $tipoQuery)->first();
        if (! $tipo?->activo || ! \Brick\Math\BigDecimal::of((string) $calibre->peso_promedio_kg)->isPositive() || $calibre->conteo_por_empaque <= 0) {
            throw ValidationException::withMessages(['catalogotamanoconteoid' => 'La presentación no tiene un empaque activo, un peso positivo o un conteo válido. Revise su configuración.']);
        }
        $calibre->setRelation('tipoEmpaque', $tipo);
        $queryUnidad = UnidadMedida::query()->whereKey($data['unidadmedidaid']);
        $unidad = ($bloquear ? $queryUnidad->lockForUpdate() : $queryUnidad)->first();
        $factor = $unidad ? CosechaDecimal::factorUnidad($unidad) : null;
        if ($factor === null) {
            throw ValidationException::withMessages(['unidadmedidaid' => 'Selecciona una unidad de peso con conversión a kg reconocida.']);
        }
        $cantidad = CosechaDecimal::cantidad($data['cantidad']);
        $kg = CosechaDecimal::kg($cantidad, $factor);
        $presentacion = $this->presentacion->desdeKg($kg, $calibre);

        return $presentacion + [
            'version' => 1, 'cantidad' => $cantidad, 'unidad_factor_kg' => $factor,
            'unidad_abreviatura' => $unidad->abreviatura, 'unidad_nombre' => $unidad->nombre,
        ];
    }

    public function vistaPrevia(Request $request): array
    {
        $data = $this->entrada($request, false);
        $lote = $this->loteVisible($request->user(), (int) $data['loteid']);

        return $this->calcular($lote, $data, false);
    }

    public function registrar(Request $request): Produccion
    {
        abort_unless(UsuarioRol::puedeOperar($request->user()) && $request->user()->can('lotes.view'), 403, 'No tienes permiso para registrar cosechas.');
        $data = $this->entrada($request, true);
        $rutaFoto = null;
        try {
            return DB::transaction(function () use ($request, $data, &$rutaFoto) {
                $lote = $this->loteVisible($request->user(), (int) $data['loteid'], true);
                if (! $this->trazabilidad->puedeRegistrarCosecha($lote)) {
                    throw ValidationException::withMessages(['loteid' => 'El lote no está listo para cosecha. Complete sus actividades de crecimiento y revise su estado.']);
                }
                abort_unless($this->puedeRegistrar($request->user(), $lote), 403, 'Solo el jefe agrícola del equipo u operario asignado a la cosecha pueden registrarla.');
                $presentacion = $this->calcular($lote, $data, true);
                $destino = DestinoProduccion::query()->whereRaw('LOWER(TRIM(nombre)) = ?', ['almacenamiento'])->first();
                if (! $destino) {
                    throw ValidationException::withMessages(['loteid' => 'Falta configurar el destino Almacenamiento antes de registrar una cosecha.']);
                }
                $rutaFoto = EvidenciaFoto::guardar($request->file('evidencia_foto'), 'producciones_evidencia');
                if (! $rutaFoto) {
                    throw new \RuntimeException('No se pudo guardar la foto de la cosecha.');
                }
                $produccion = Produccion::create([
                    'loteid' => $lote->loteid, 'cantidad' => $presentacion['cantidad'],
                    'unidadmedidaid' => $data['unidadmedidaid'], 'cantidad_base' => $presentacion['kg'],
                    'catalogotamanoconteoid' => $presentacion['calibre_id'],
                    'cantidad_unidades' => $presentacion['unidades'], 'cantidad_empaques' => $presentacion['empaques'],
                    'presentacion_cosecha' => $presentacion, 'fechacosecha' => $data['fechacosecha'] ?? now()->toDateString(),
                    'destinoproduccionid' => $destino->destinoproduccionid,
                    'observaciones' => $data['observaciones'] ?? null, 'imagenurl' => 'storage/'.$rutaFoto,
                ]);
                $estado = EstadoLoteCatalogo::idPorSlug('cosechado');
                if (! $estado) {
                    throw ValidationException::withMessages(['loteid' => 'Falta configurar el estado Cosechado.']);
                }
                $lote->update(['estadolotetipoid' => $estado, 'fechamodificacion' => now()]);
                HistorialEstadoLote::create([
                    'loteid' => $lote->loteid, 'estadolotetipoid' => $estado, 'fecha_cambio' => now(),
                    'observaciones' => 'Cosecha: '.$presentacion['cantidad'].' '.$presentacion['unidad_abreviatura'].' · '.$presentacion['kg'].' kg · '.$presentacion['resumen'],
                    'usuarioid' => $request->user()->usuarioid, 'created_at' => now(), 'updated_at' => now(),
                ]);

                return $produccion->fresh(['unidadMedida']);
            });
        } catch (\Throwable $e) {
            if ($rutaFoto) {
                Storage::disk('public')->delete($rutaFoto);
            }
            throw $e;
        }
    }
}
