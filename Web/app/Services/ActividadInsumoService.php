<?php

namespace App\Services;

use App\Models\Actividad;
use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\EstadoLoteInsumo;
use App\Models\Insumo;
use App\Models\Lote;
use App\Models\LoteInsumo;
use App\Models\TipoInsumo;
use App\Models\TipoMovimientoAlmacen;
use App\Support\ActividadDetalleCatalogo;
use App\Support\CampoAccess;
use App\Support\InsumoCatalogo;
use App\Support\InsumoImagenCatalogo;
use App\Support\PedidoCatalogo;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

class ActividadInsumoService
{
    /**
     * @return array<string, mixed>
     */
    public function parseDetalleDesdeRequest(Request $request, ?string $tipoActividadNombre): array
    {
        $raw = $request->input('detalle_actividad_json');
        if (is_string($raw) && trim($raw) !== '') {
            $decoded = json_decode($raw, true);

            return is_array($decoded) ? $decoded : [];
        }

        return [];
    }

    /**
     * @param  array<string, mixed>  $detalle
     * @return array<string, mixed>
     */
    public function validarDetalle(array $detalle, ?string $tipoActividadNombre, ?Lote $lote = null): array
    {
        if (ActividadDetalleCatalogo::esRiego($tipoActividadNombre)) {
            $tipoRiego = trim((string) ($detalle['riego']['key'] ?? ''));
            if ($tipoRiego === '') {
                throw ValidationException::withMessages([
                    'detalle_actividad_json' => 'Seleccione el tipo de riego en el modal.',
                ]);
            }

            return [
                'modo' => 'riego',
                'riego' => [
                    'key' => $tipoRiego,
                    'label' => trim((string) ($detalle['riego']['label'] ?? $tipoRiego)),
                ],
                'stock_aplicado' => false,
            ];
        }

        $slug = ActividadDetalleCatalogo::slugInsumoParaTipoActividad($tipoActividadNombre);
        if ($slug === null) {
            return [];
        }

        $filas = collect($detalle['insumos'] ?? [])
            ->filter(fn ($f) => is_array($f) && (int) ($f['insumoid'] ?? 0) > 0)
            ->values();

        if ($filas->isEmpty()) {
            throw ValidationException::withMessages([
                'detalle_actividad_json' => 'Seleccione al menos un insumo en el modal.',
            ]);
        }

        $max = ActividadDetalleCatalogo::maxInsumosPorTipo($tipoActividadNombre);
        if ($filas->count() > $max) {
            throw ValidationException::withMessages([
                'detalle_actividad_json' => $max === 1
                    ? 'En siembra solo puede usar un material.'
                    : 'Demasiados insumos seleccionados.',
            ]);
        }

        $almacen = $lote ? CampoAccess::almacenAgricolaParaLote($lote) : null;

        $normalizados = [];
        foreach ($filas as $fila) {
            $insumo = Insumo::query()->with(['tipo', 'unidadMedida'])->find((int) $fila['insumoid']);
            if ($insumo === null || ! InsumoCatalogo::esInsumoOperativo($insumo)) {
                throw ValidationException::withMessages([
                    'detalle_actividad_json' => 'Uno de los insumos seleccionados no es válido.',
                ]);
            }

            if ($almacen !== null) {
                $this->assertInsumoDeAlmacenOperativo($insumo, $almacen);
            } elseif (Schema::hasColumn('insumo', 'almacenid') && $insumo->almacenid === null) {
                throw ValidationException::withMessages([
                    'detalle_actividad_json' => 'El insumo «'.$insumo->nombre.'» es legacy (sin almacén) y no puede usarse en consumo agrícola operativo.',
                ]);
            }

            $insumoSlug = InsumoCatalogo::slugFromNombreTipo($insumo->tipo?->nombre);
            if ($insumoSlug !== $slug) {
                throw ValidationException::withMessages([
                    'detalle_actividad_json' => 'El insumo «'.$insumo->nombre.'» no corresponde a esta actividad.',
                ]);
            }

            $cantidad = (float) ($fila['cantidad'] ?? 0);
            if ($cantidad <= 0) {
                throw ValidationException::withMessages([
                    'detalle_actividad_json' => 'Indique una cantidad mayor a cero para «'.$insumo->nombre.'».',
                ]);
            }

            $unidad = $insumo->unidadMedida?->abreviatura ?? $insumo->unidadMedida?->nombre ?? 'ud';
            if ((float) $insumo->stock < $cantidad) {
                throw ValidationException::withMessages([
                    'detalle_actividad_json' => 'Stock insuficiente de «'.$insumo->nombre.'». Disponible: '
                        .number_format((float) $insumo->stock, 2).' '.$unidad
                        .'; intentó aplicar: '.number_format($cantidad, 2).' '.$unidad.'.',
                ]);
            }

            $normalizados[] = [
                'insumoid' => (int) $insumo->insumoid,
                'nombre' => $insumo->nombre,
                'cantidad' => $cantidad,
                'unidad' => $unidad,
                'almacenid' => $insumo->almacenid ? (int) $insumo->almacenid : null,
            ];
        }

        return [
            'modo' => 'insumos',
            'insumos' => $normalizados,
            'almacenid' => $almacen?->almacenid,
            'stock_aplicado' => false,
        ];
    }

    /**
     * OPA-08 — descuenta solo de la existencia del almacén agrícola del lote.
     *
     * @param  array<string, mixed>  $detalle
     */
    public function aplicarStockSiCorresponde(Actividad $actividad, array &$detalle): void
    {
        if (($detalle['modo'] ?? '') !== 'insumos') {
            return;
        }
        DB::transaction(function () use ($actividad, &$detalle) {
            if (DB::getDriverName() === 'sqlite') {
                DB::table('actividad')->where('actividadid', $actividad->actividadid)->update(['descripcion' => DB::raw('descripcion')]);
            }
            $locked = Actividad::query()->whereKey($actividad->actividadid)->lockForUpdate()->firstOrFail();
            $persistido = json_decode($locked->detalle_json ?? '', true) ?: [];
            if (! empty($persistido['stock_aplicado'])) {
                $detalle = $persistido;
                return;
            }
            $locked->loadMissing(['lote', 'tipoActividad']);
            $almacen = CampoAccess::almacenAgricolaParaLote($locked->lote);
            $filas = $detalle['insumos'] ?? [];
            $max = ActividadDetalleCatalogo::maxInsumosPorTipo($locked->tipoActividad?->nombre);
            if (count($filas) > $max) {
                throw ValidationException::withMessages(['consumos' => "Se admiten como máximo $max insumos para esta actividad."]);
            }
            $ids = array_map(fn ($f) => (int) $f['insumoid'], $filas);
            if (count($ids) !== count(array_unique($ids))) {
                throw ValidationException::withMessages(['consumos' => 'No repitas el mismo insumo; registra su cantidad total.']);
            }
            $existencias = app(InventarioExistenciaService::class)->bloquear($ids);
            $normalizados = [];
            foreach ($filas as $i => $fila) {
                $indice = $fila['_indice'] ?? $i;
                $insumo = $existencias->get((int) $fila['insumoid']);
                if (! $insumo || ! InsumoCatalogo::esInsumoOperativo($insumo)) {
                    throw ValidationException::withMessages(["consumos.$indice.insumoid" => 'Selecciona un insumo operativo válido.']);
                }
                if ((int) $insumo->almacenid !== (int) $almacen->almacenid
                    || (isset($fila['almacenid']) && (int) $fila['almacenid'] !== (int) $almacen->almacenid)) {
                    throw ValidationException::withMessages(["consumos.$indice.almacenid" => 'El insumo no pertenece al almacén agrícola del lote.']);
                }
                $slug = ActividadDetalleCatalogo::slugInsumoParaTipoActividad($locked->tipoActividad?->nombre);
                if ($slug === null || InsumoCatalogo::slugFromNombreTipo($insumo->tipo?->nombre) !== $slug) {
                    throw ValidationException::withMessages(["consumos.$indice.insumoid" => 'El tipo de insumo no corresponde a esta actividad.']);
                }
                try {
                    $cantidad = \App\Support\InventarioDecimal::consumo($fila['cantidad']);
                } catch (\InvalidArgumentException $e) {
                    throw ValidationException::withMessages(["consumos.$indice.cantidad" => $e->getMessage()]);
                }
                if (isset($fila['unidadmedidaid']) && (int) $fila['unidadmedidaid'] !== (int) $insumo->unidadmedidaid) {
                    throw ValidationException::withMessages(["consumos.$indice.unidadmedidaid" => 'Usa la unidad del insumo sin conversiones.']);
                }
                if (\App\Support\InventarioDecimal::unidades($insumo->getRawOriginal('stock')) < \App\Support\InventarioDecimal::unidades($cantidad)) {
                    throw ValidationException::withMessages(["consumos.$indice.cantidad" => 'Stock insuficiente en el almacén autorizado.']);
                }
                $normalizados[] = ['insumoid' => (int) $insumo->insumoid, 'almacenid' => (int) $almacen->almacenid,
                    'materiaprimaloteid' => isset($fila['materiaprimaloteid']) ? (int) $fila['materiaprimaloteid'] : null,
                    'inventario_presentacion_loteid' => isset($fila['inventario_presentacion_loteid']) ? (int) $fila['inventario_presentacion_loteid'] : null,
                    'cantidad' => $cantidad, 'nombre' => $insumo->nombre, 'unidadmedidaid' => (int) $insumo->unidadmedidaid,
                    'unidad' => $insumo->unidadMedida?->abreviatura ?? $insumo->unidadMedida?->nombre ?? 'ud'];
            }
            // All current stocks were checked while locked; write in the same deterministic order.
            usort($normalizados, fn ($a, $b) => $a['insumoid'] <=> $b['insumoid']);
            $tipoSalida = $this->tipoMovimientoSalidaConsumoActividad();
            $estadoId = $this->idEstadoAplicado();
            foreach ($normalizados as $fila) {
                $insumo = $existencias->get($fila['insumoid']);
                $saldoAnterior = $insumo->getRawOriginal('stock');
                try {
                    $insumo->decrementarStock($fila['cantidad'], $fila['materiaprimaloteid'], false, null, $fila['inventario_presentacion_loteid']);
                } catch (ValidationException $e) {
                    $indice = array_search($fila['insumoid'], array_column($filas, 'insumoid'));
                    throw ValidationException::withMessages(collect($e->errors())->mapWithKeys(fn ($mensajes, $campo) => ["consumos.$indice.$campo" => $mensajes])->all());
                }
                AlmacenMovimiento::create([
                    'almacenid' => $almacen->almacenid, 'insumoid' => $insumo->insumoid,
                    'tipo_movimiento_almacenid' => $tipoSalida->tipo_movimiento_almacenid,
                    'usuarioid' => $actividad->usuarioid_ejecutor ?: $actividad->usuarioid,
                    'fecha' => now()->toDateString(), 'cantidad' => $fila['cantidad'],
                    'materiaprimaloteid' => $fila['materiaprimaloteid'] ?: null,
                    'inventario_presentacion_loteid' => $fila['inventario_presentacion_loteid'],
                    'unidadmedidaid' => $insumo->unidadmedidaid, 'saldo_anterior' => $saldoAnterior, 'saldo_posterior' => $insumo->getRawOriginal('stock'),
                    'referencia' => 'ACT-'.$actividad->actividadid, 'destino_motivo' => 'Lote #'.$actividad->loteid,
                    'observaciones' => '[Consumo actividad #'.$actividad->actividadid.'] '.$insumo->nombre,
                ]);
                LoteInsumo::create([
                    'loteid' => $actividad->loteid, 'actividadid' => $actividad->actividadid,
                    'insumoid' => $insumo->insumoid, 'usuarioid' => $actividad->usuarioid,
                    'cantidadusada' => $fila['cantidad'], 'fechauo' => now(), 'costototal' => 0,
                    'estadoloteinsumoid' => $estadoId, 'observaciones' => 'Actividad #'.$actividad->actividadid,
                ]);
            }
            $detalle['modo'] = 'insumos';
            $detalle['insumos'] = $normalizados;
            $detalle['stock_aplicado'] = true;
            $detalle['almacenid'] = (int) $almacen->almacenid;
            $locked->update(['detalle_json' => json_encode($detalle, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)]);
        });
    }
    /**
     * @return array<int, array<string, mixed>>
     */
    public function listarInsumosParaModal(string $tipoSlug, ?Lote $lote = null): array
    {
        $tipoIds = TipoInsumo::query()
            ->get(['tipoinsumoid', 'nombre'])
            ->filter(fn (TipoInsumo $t) => InsumoCatalogo::slugFromNombreTipo($t->nombre) === $tipoSlug)
            ->pluck('tipoinsumoid')
            ->map(fn ($id) => (int) $id)
            ->values()
            ->all();

        if ($tipoIds === []) {
            return [];
        }

        $query = InsumoCatalogo::aplicarFiltroOperativo(
            Insumo::query()->with(['tipo', 'unidadMedida'])
        )->whereIn('tipoinsumoid', $tipoIds)
            ->where('stock', '>', 0)
            ->orderBy('nombre');

        // AGR-04: solo existencias del almacén agrícola operativo del jefe del lote.
        // Legacy (almacenid null) excluido del selector operativo.
        if ($lote !== null && Schema::hasColumn('insumo', 'almacenid')) {
            try {
                $almacen = CampoAccess::almacenAgricolaParaLote($lote);
            } catch (ValidationException) {
                // Sin almacén inequívoco no ofrecemos catálogo global ni legacy.
                return [];
            }
            $query->where('almacenid', (int) $almacen->almacenid);
        } elseif (Schema::hasColumn('insumo', 'almacenid')) {
            $query->whereNotNull('almacenid');
        }

        $referenciaNombre = null;
        $insumoPlanificadoId = null;
        if ($lote) {
            $lote->loadMissing('insumoSemilla', 'cultivo');
            if ($lote->insumoSemilla) {
                $insumoPlanificadoId = (int) $lote->insumosemillaid;
                $referenciaNombre = PedidoCatalogo::cultivoDesdeInsumo($lote->insumoSemilla);
            } else {
                $referenciaNombre = $lote->cultivo?->nombre;
            }
        }

        if ($tipoSlug === 'material_siembra' && $insumoPlanificadoId) {
            $planificado = (clone $query)->where('insumoid', $insumoPlanificadoId)->first();
            $resto = $query->get()->reject(fn (Insumo $i) => (int) $i->insumoid === $insumoPlanificadoId);

            $coleccion = collect($planificado ? [$planificado] : [])->merge($resto);

            return $coleccion->map(fn (Insumo $i) => self::mapearInsumoModal($i, $lote, $tipoSlug))->values()->all();
        }

        if ($tipoSlug === 'material_siembra' && $referenciaNombre) {
            $candidatos = (clone $query)->get();
            $filtrados = $candidatos->filter(function (Insumo $i) use ($referenciaNombre) {
                $nombre = mb_strtolower($i->nombre);
                $palabras = preg_split('/\s+/u', mb_strtolower($referenciaNombre)) ?: [];
                foreach ($palabras as $palabra) {
                    if (mb_strlen($palabra) >= 3 && str_contains($nombre, $palabra)) {
                        return true;
                    }
                }

                return false;
            });
            if ($filtrados->isNotEmpty()) {
                return $filtrados->map(fn (Insumo $i) => self::mapearInsumoModal($i, $lote, $tipoSlug))->values()->all();
            }
        }

        return $query->get()->map(fn (Insumo $i) => self::mapearInsumoModal($i, $lote, $tipoSlug))->values()->all();
    }

    /** @return array<string, mixed> */
    private static function mapearInsumoModal(Insumo $i, ?Lote $lote = null, ?string $tipoSlug = null): array
    {
        $data = [
            'id' => (int) $i->insumoid,
            'nombre' => $i->nombre,
            'stock' => (float) $i->stock,
            'almacenid' => $i->almacenid ? (int) $i->almacenid : null,
            'unidad' => $i->unidadMedida?->abreviatura ?? $i->unidadMedida?->nombre ?? 'ud',
            'unidad_nombre' => $i->unidadMedida?->nombre ?? 'Unidad',
            'imagen' => InsumoImagenCatalogo::urlPara($i),
        ];

        if ($lote && in_array($tipoSlug, ['fertilizantes', 'pesticidas'], true)) {
            $sug = \App\Support\CultivoSiembraCatalogo::sugerenciaAplicacionInsumo($i, (float) $lote->superficie);
            $data['sugerencia'] = $sug['tiene_dosis'] ? $sug['sugerido'] : null;
            $data['sugerencia_detalle'] = $sug;
        }

        return $data;
    }

    private function assertInsumoDeAlmacenOperativo(Insumo $insumo, Almacen $almacen): void
    {
        if (! Schema::hasColumn('insumo', 'almacenid')) {
            return;
        }

        if ($insumo->almacenid === null) {
            throw ValidationException::withMessages([
                'detalle_actividad_json' => 'El insumo «'.$insumo->nombre.'» es legacy (sin almacén) y no puede usarse para consumo agrícola operativo.',
            ]);
        }

        if ((int) $insumo->almacenid !== (int) $almacen->almacenid) {
            throw ValidationException::withMessages([
                'detalle_actividad_json' => 'El insumo «'.$insumo->nombre.'» no pertenece al almacén agrícola «'.$almacen->nombre.'».',
            ]);
        }
    }

    private function tipoMovimientoSalidaConsumoActividad(): TipoMovimientoAlmacen
    {
        $tipo = TipoMovimientoAlmacen::query()
            ->where('naturaleza', 'salida')
            ->where('activo', true)
            ->get()
            ->first(fn (TipoMovimientoAlmacen $t) => in_array(
                TipoMovimientoAlmacen::normalizeNombre($t->nombre),
                ['consumo actividad', 'consumo interno', 'aplicacion campo', 'aplicación campo', 'salida'],
                true
            ));

        if ($tipo) {
            return $tipo;
        }

        $fallback = TipoMovimientoAlmacen::activosPorNaturaleza('salida')->first();
        if ($fallback) {
            return $fallback;
        }

        return TipoMovimientoAlmacen::query()->firstOrCreate(
            ['nombre' => 'Consumo actividad', 'naturaleza' => 'salida'],
            ['activo' => true]
        );
    }

    private function idEstadoAplicado(): int
    {
        return (int) (EstadoLoteInsumo::query()
            ->whereRaw('LOWER(nombre) = ?', ['aplicado'])
            ->value('estadoloteinsumoid')
            ?? EstadoLoteInsumo::query()->firstOrCreate(['nombre' => 'Aplicado'], ['nombre' => 'Aplicado'])->estadoloteinsumoid);
    }
}
