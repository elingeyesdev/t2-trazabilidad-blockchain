<?php

namespace App\Services;

use App\Models\Actividad;
use App\Models\Insumo;
use App\Models\Lote;
use App\Support\ActividadDetalleCatalogo;
use App\Support\ActividadPermisos;
use App\Support\ActividadSecuenciaService;
use App\Support\CampoAccess;
use App\Support\InventarioDecimal;
use App\Support\LoteEstadoPorActividad;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class ActividadCierreService
{
    public static function reglas(): array
    {
        return [
            'resultado' => 'required|string|max:250',
            'evidencia_foto' => 'required|file|image|mimes:jpg,jpeg,png,webp|mimetypes:image/jpeg,image/png,image/webp|max:5120',
            'consumos' => 'sometimes|array|max:10',
            'consumos.*' => 'array:insumoid,almacenid,cantidad,unidadmedidaid,materiaprimaloteid,inventario_presentacion_loteid,partida',
            'consumos.*.materiaprimaloteid' => 'sometimes|nullable|integer|min:0',
            'consumos.*.inventario_presentacion_loteid' => 'sometimes|nullable|integer|min:1',
            'consumos.*.partida' => 'sometimes|nullable|string|max:40',
            'consumos.*.insumoid' => 'required|integer|exists:insumo,insumoid|distinct',
            'consumos.*.almacenid' => 'required|integer|exists:almacen,almacenid',
            'consumos.*.cantidad' => ['required', 'regex:/^(?:0|[1-9][0-9]{0,10})(?:\.[0-9]{1,3})?$/D'],
            'consumos.*.unidadmedidaid' => 'sometimes|required|integer|exists:unidadmedida,unidadmedidaid',
            'usuarioid' => 'missing', 'usuarioid_ejecutor' => 'missing',
            'fechafin' => 'missing', 'estado' => 'missing', 'stock' => 'missing',
            'evidencia_foto_path' => 'missing', 'detalle_json' => 'missing',
        ];
    }

    /** Web and API share this transaction and file compensation boundary. */
    public function cerrar(Request $request, Actividad $actividad, ?\Closure $resolver = null): Actividad
    {
        abort_unless(ActividadPermisos::puedeEjecutarCierre($request->user(), $actividad), 403, 'No tienes permiso para cerrar esta actividad.');
        $data = $request->validate(self::reglas(), [
            'resultado.required' => 'Describe el resultado de la actividad.',
            'evidencia_foto.required' => 'Debe subir una foto del trabajo realizado.',
            'evidencia_foto.max' => 'La imagen no puede superar 5 MB.',
            'consumos.*.insumoid.distinct' => 'No repitas el mismo insumo; indica su cantidad total en una sola línea.',
            'consumos.*.cantidad.regex' => 'Indica una cantidad positiva con hasta tres decimales.',
            'missing' => 'El campo :attribute se establece en el servidor.',
        ]);
        $foto = $request->file('evidencia_foto');
        if (@getimagesize($foto->getRealPath()) === false) {
            throw ValidationException::withMessages(['evidencia_foto' => 'El contenido del archivo no es una imagen válida.']);
        }
        $shaFoto = hash_file('sha256', $foto->getRealPath());
        $nuevoPath = null;

        try {
            return DB::transaction(function () use ($request, $actividad, $data, $foto, $shaFoto, $resolver, &$nuevoPath) {
                if (DB::getDriverName() === 'sqlite') {
                    DB::table('lote')->where('loteid', $actividad->loteid)->update(['nombre' => DB::raw('nombre')]);
                }
                // All activity closings serialize on the lot first, then the activity.
                Lote::query()->whereKey($actividad->loteid)->lockForUpdate()->firstOrFail();
                $locked = $resolver ? $resolver() : Actividad::query()->whereKey($actividad->actividadid)->lockForUpdate()->firstOrFail();
                $locked->load(['lote', 'tipoActividad']);
                abort_unless(ActividadPermisos::puedeEjecutarCierre($request->user(), $locked), 403, 'No tienes permiso para cerrar esta actividad.');
                $detalle = json_decode($locked->detalle_json ?? '', true) ?: [];
                $filasEntrada = $data['consumos'] ?? ($detalle['insumos'] ?? []);
                if (! array_key_exists('consumos', $data) && $filasEntrada === []
                    && str_contains(mb_strtolower($locked->tipoActividad?->nombre ?? ''), 'siembra')
                    && $locked->lote->insumosemillaid && $locked->lote->cantidad_semilla_planificada !== null) {
                    $semilla = Insumo::find($locked->lote->insumosemillaid);
                    $filasEntrada = [['insumoid' => $locked->lote->insumosemillaid,
                        'almacenid' => $semilla?->almacenid, 'cantidad' => $locked->lote->getRawOriginal('cantidad_semilla_planificada')]];
                }
                $filas = $this->normalizarConsumos($filasEntrada);
                $huella = hash('sha256', json_encode([
                    'resultado' => trim($data['resultado']), 'foto' => $shaFoto,
                    'ejecutor' => (int) $request->user()->usuarioid, 'consumos' => $filas,
                ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));

                if ($locked->fechafin !== null) {
                    abort_unless(hash_equals((string) ($detalle['cierre']['huella'] ?? ''), $huella), 409, 'La actividad ya tiene un cierre confirmado diferente.');
                    return $locked; // No new file, movement, result or stock change.
                }
                if (! empty($detalle['stock_aplicado'])) {
                    abort_unless($filas === $this->normalizarConsumos($detalle['insumos'] ?? []), 409, 'Los consumos de esta actividad ya fueron registrados y no pueden sustituirse al cerrar.');
                }
                app(ActividadSecuenciaService::class)->asegurarEnTurnoParaCompletar($locked);
                $bloqueo = app(\App\Support\LoteTrazabilidadService::class)->tipoActividadPermitidoEnFase(
                    $locked->tipoActividad?->nombre, app(\App\Support\LoteTrazabilidadService::class)->resolverFaseActual($locked->lote)
                );
                if (! $bloqueo) {
                    throw ValidationException::withMessages(['actividadid' => 'La fase actual del lote no permite cerrar esta actividad.']);
                }
                if (ActividadDetalleCatalogo::requiereInsumos($locked->tipoActividad?->nombre) && $filas === []) {
                    throw ValidationException::withMessages(['consumos' => 'Indica los insumos realmente consumidos al realizar esta actividad.']);
                }
                if (str_contains(mb_strtolower($locked->tipoActividad?->nombre ?? ''), 'siembra')
                    && $locked->lote->insumosemillaid
                    && $filas !== []) {
                    $semillaPlanId = (int) $locked->lote->insumosemillaid;
                    $semillaPlanNombre = Insumo::query()->whereKey($semillaPlanId)->value('nombre') ?? 'semilla planificada';
                    foreach ($filas as $i => $fila) {
                        if ((int) $fila['insumoid'] !== $semillaPlanId) {
                            $indice = array_search($fila['insumoid'], array_column($filasEntrada, 'insumoid'));
                            $indice = $indice === false ? $i : $indice;
                            throw ValidationException::withMessages([
                                "consumos.$indice.insumoid" => "Esta siembra corresponde a «{$semillaPlanNombre}» (elegida al crear el lote) y no puede cambiarse por otro insumo.",
                            ]);
                        }
                    }
                }
                if ($filas !== []) {
                    $almacen = CampoAccess::almacenAgricolaParaLote($locked->lote);
                    foreach ($filas as $i => &$fila) {
                        if ($fila['almacenid'] !== (int) $almacen->almacenid || ! CampoAccess::puedeVerAlmacen($request->user(), $almacen)) {
                            $indice = array_search($fila['insumoid'], array_column($filasEntrada, 'insumoid'));
                            $indice = $indice === false ? $i : $indice;
                            throw ValidationException::withMessages(["consumos.$indice.almacenid" => 'Selecciona el almacén agrícola autorizado para este lote.']);
                        }
                    }
                    unset($fila);
                    // Keep existing type/warehouse rules, then lock and recheck current stock
                    // in ActividadInsumoService; never trust a pre-transaction stock snapshot.
                    $detalle['modo'] = 'insumos';
                    $detalle['insumos'] = $filas;
                    foreach ($detalle['insumos'] as $i => &$fila) {
                        $indice = array_search($fila['insumoid'], array_column($data['consumos'] ?? $filas, 'insumoid'));
                        $fila['_indice'] = $indice === false ? $i : $indice;
                    }
                    unset($fila);
                    $detalle['stock_aplicado'] = false;
                    app(ActividadInsumoService::class)->aplicarStockSiCorresponde($locked, $detalle);
                }

                $carpeta = 'actividades_privadas/'.$locked->actividadid;
                $nombre = \Illuminate\Support\Str::uuid().'.'.$foto->guessExtension();
                if (Storage::disk('local')->exists($carpeta.'/'.$nombre)) {
                    throw new \RuntimeException('No se pudo generar un nombre de archivo único.');
                }
                $nuevoPath = $carpeta.'/'.$nombre;
                $guardado = Storage::disk('local')->putFileAs($carpeta, $foto, $nombre);
                if (! $guardado || ! Storage::disk('local')->exists($nuevoPath)) {
                    throw new \RuntimeException('No se pudo guardar la fotografía de cierre.');
                }
                $detalle['cierre'] = ['resultado' => trim($data['resultado']), 'foto_sha256' => $shaFoto, 'huella' => $huella];
                $locked->fill([
                    'evidencia_foto_path' => $nuevoPath,
                    'usuarioid_ejecutor' => $request->user()->usuarioid,
                    'fechafin' => now(),
                    'detalle_json' => json_encode($detalle, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
                ])->save();
                app(LoteEstadoPorActividad::class)->aplicarDesdeActividad($locked);
                if (str_contains(mb_strtolower($locked->tipoActividad?->nombre ?? ''), 'siembra') && ! $locked->lote->fechasiembra) {
                    $locked->lote->update(['fechasiembra' => $locked->fechafin->toDateString(), 'fechamodificacion' => now()]);
                }
                app(NotificacionUsuarioService::class)->descartarActividadAsignada((int) $locked->actividadid);

                return $locked;
            });
        } catch (\Throwable $error) {
            if (is_string($nuevoPath)) {
                try {
                    if (! Storage::disk('local')->delete($nuevoPath)) {
                        Log::warning('Limpieza pendiente de foto de cierre no confirmado', ['disk' => 'local', 'path' => $nuevoPath]);
                    }
                } catch (\Throwable $limpieza) {
                    Log::warning('Limpieza pendiente de foto de cierre no confirmado', ['disk' => 'local', 'path' => $nuevoPath]);
                }
            }
            throw $error;
        }
    }

    private function normalizarConsumos(array $filas): array
    {
        if (count($filas) > 10) {
            throw ValidationException::withMessages(['consumos' => 'No se admiten más de diez consumos.']);
        }
        $normalizados = [];
        foreach ($filas as $i => $fila) {
            $fila = app(InventarioExistenciaService::class)->seleccion($fila);
            try {
                $cantidad = InventarioDecimal::consumo($fila['cantidad'] ?? '0');
            } catch (\InvalidArgumentException $error) {
                throw ValidationException::withMessages(["consumos.$i.cantidad" => $error->getMessage()]);
            }
            $id = (int) ($fila['insumoid'] ?? 0);
            if (isset($normalizados[$id])) {
                throw ValidationException::withMessages(["consumos.$i.insumoid" => 'No repitas el mismo insumo; indica su consumo total.']);
            }
            $insumo = Insumo::find($id);
            if (! $insumo) {
                throw ValidationException::withMessages(["consumos.$i.insumoid" => 'Selecciona un insumo válido.']);
            }
            if (isset($fila['unidadmedidaid']) && (int) $fila['unidadmedidaid'] !== (int) $insumo->unidadmedidaid) {
                throw ValidationException::withMessages(["consumos.$i.unidadmedidaid" => 'Usa la unidad del insumo; no se realizan conversiones.']);
            }
            $normalizados[$id] = ['insumoid' => $id, 'almacenid' => (int) ($fila['almacenid'] ?? $insumo->almacenid), 'cantidad' => $cantidad];
            if (array_key_exists('materiaprimaloteid', $fila) && $fila['materiaprimaloteid'] !== null) {
                $normalizados[$id]['materiaprimaloteid'] = (int) $fila['materiaprimaloteid'];
            }
            if (isset($fila['inventario_presentacion_loteid'])) {
                $normalizados[$id]['inventario_presentacion_loteid'] = (int) $fila['inventario_presentacion_loteid'];
            }
        }
        ksort($normalizados, SORT_NUMERIC);

        return array_values($normalizados);
    }
}
