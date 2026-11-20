<?php

namespace App\Services;

use App\Models\Actividad;
use App\Models\Almacen;
use App\Models\AsignacionEtapaPlanta;
use App\Models\Insumo;
use App\Models\LoteProduccionPedido;
use App\Models\Usuario;
use App\Support\ActividadPermisos;
use App\Support\AlmacenAcceso;
use App\Support\ProduccionPlantaAcceso;
use App\Support\RecorridoFiltros;
use App\Support\UsuarioRol;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Collection;

/** Each indicator and its detail come from the same authorized, filtered population. */
final class RecorridoIndicadoresService
{
    public function consultar(Usuario $usuario, array $f): array
    {
        abort_unless($usuario->can('lotes.view') || $usuario->can('lote_produccion.view')
            || $usuario->can('inventario.view'), 403);
        $pendientes = collect();
        if ($usuario->can('lotes.view')) {
            $query = Actividad::whereNull('fechafin')->with('tipoActividad');
            ActividadPermisos::aplicarScopeVisibles($query, $usuario);
            foreach ($query->orderBy('actividadid')->get() as $a) {
                $fecha = $a->fecha_planificada?->toDateString();
                // Pending agricultural work has no direct warehouse: keep it as unrelated context.
                if (RecorridoFiltros::coincide($fecha, null, $f, false)) {
                    $pendientes->push(['tipo' => 'actividad_agricola', 'id' => (int) $a->getKey(),
                        'descripcion' => $a->tipoActividad?->nombre ?? $a->descripcion,
                        'responsable_id' => $a->usuarioid_ejecutor ?? $a->usuarioid,
                        'fecha' => $fecha, 'significado_fecha' => 'programación', 'estado' => 'pendiente',
                        'loteid' => $a->loteid, 'almacen_filtro_aplica' => false]);
                }
            }
        }
        if ($usuario->can('lote_produccion.view')) {
            $lotes = ProduccionPlantaAcceso::scope(LoteProduccionPedido::query(), $usuario)->select('loteproduccionpedidoid');
            $query = AsignacionEtapaPlanta::pendientes()->whereIn('loteproduccionpedidoid', $lotes);
            if (UsuarioRol::esOperarioPlanta($usuario)) {
                $query->where('operador_usuarioid', $usuario->getKey());
            }
            if (! empty($f['almacenid'])) {
                $query->whereHas('loteProduccion', fn ($q) => $q->whereHas('materiasPrimas.insumo', fn ($i) => $i->where('almacenid', $f['almacenid']))
                    ->orWhereHas('almacenajes', fn ($a) => $a->where('almacenid', $f['almacenid'])));
            }
            foreach ($query->with('proceso')->orderBy('asignacionetapaplantaid')->get() as $a) {
                $fecha = $a->creado_en?->toIso8601String();
                if (RecorridoFiltros::coincide($fecha, null, $f, false)) {
                    $pendientes->push(['tipo' => 'etapa_planta', 'id' => (int) $a->getKey(), 'descripcion' => $a->proceso?->nombre,
                        'responsable_id' => $a->operador_usuarioid, 'fecha' => $fecha, 'significado_fecha' => 'asignación',
                        'estado' => $a->estado, 'loteproduccionpedidoid' => $a->loteproduccionpedidoid, 'almacen_filtro_aplica' => true]);
                }
            }
        }
        $bajas = collect();
        $almacenes = $usuario->can('inventario.view') ? AlmacenAcceso::idsVisibles($usuario) : [];
        if ($usuario->can('inventario.view')) {
            $query = Insumo::whereIn('almacenid', $almacenes)->whereNotNull('stockminimo')->with(['unidadMedida', 'almacen']);
            $query->when($f['almacenid'] ?? null, fn ($q, $id) => $q->where('almacenid', $id));
            foreach ($query->orderBy('almacenid')->orderBy('insumoid')->get() as $i) {
                $saldo = app(InventarioExistenciaService::class)->resumen($i);
                if ($saldo['existencias_bajas']) {
                    $bajas->push(['insumoid' => (int) $i->getKey(), 'nombre' => $i->nombre,
                        'almacenid' => (int) $i->almacenid, 'almacen' => $i->almacen?->nombre,
                        'unidad' => $i->unidadMedida?->abreviatura ?: $i->unidadMedida?->nombre,
                        ...array_intersect_key($saldo, array_flip(['cantidad_fisica', 'cantidad_disponible', 'cantidad_reservada',
                            'cantidad_bloqueada', 'cantidad_vencida', 'minimo', 'saldo_coherente']))]);
                }
            }
        }
        $pendientes = $pendientes->sortBy(fn ($t) => ($t['fecha'] ?? '9999').':'.$t['tipo'].':'.str_pad((string) $t['id'], 12, '0', STR_PAD_LEFT))->values();

        return ['indicadores' => [
            'tareas_pendientes' => ($usuario->can('lotes.view') || $usuario->can('lote_produccion.view')) ? $pendientes->count() : null,
            'registros_producto_almacen_bajos' => $usuario->can('inventario.view') ? $bajas->count() : null,
        ], 'pendientes' => $this->pagina($pendientes, 'pendientes_page', $f), 'existencias_bajas' => $this->pagina($bajas, 'bajas_page', $f),
            'almacenes' => Almacen::whereIn('almacenid', $almacenes)->orderBy('nombre')->get(['almacenid', 'nombre'])->toArray(),
            'alcance' => [
                'zona_horaria' => config('app.timezone'), 'limites' => 'Fechas inclusivas; máximo 366 días.',
                'pendientes' => 'Agricultura: sin fecha de cierre, fecha_planificada (programación); almacén no aplica. Planta: estado pendiente, creado_en (asignación); almacén de materia prima o ingreso del lote. Programadas se consultan en el módulo de planta.',
                'existencias_bajas' => 'Saldo actual disponible <= mínimo configurado por registro producto–almacén. Incluye mínimo cero; excluye mínimo sin configurar. El filtro de fecha NO aplica; almacén es ubicación actual.',
                'consistencia' => 'Conteo y detalle usan la misma población; sin caché. Secciones consultadas sucesivamente, sin prometer una fotografía transaccional global.',
            ]];
    }

    private function pagina(Collection $datos, string $nombre, array $f): LengthAwarePaginator
    {
        $pagina = (int) ($f[$nombre] ?? 1);
        $cantidad = (int) ($f['per_page'] ?? 20);

        return (new LengthAwarePaginator($datos->forPage($pagina, $cantidad)->values(), $datos->count(), $cantidad, $pagina,
            ['path' => request()->url(), 'pageName' => $nombre]))->withQueryString();
    }
}
