<?php

namespace App\Support;

use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Models\Usuario;

/** Recorrido actual autorizado; una emisión conserva una copia independiente de estos datos. */
class ProductoAntecedentesService
{
    public function campo(Lote $lote, Usuario $usuario): array
    {
        abort_unless(CertificadoAcceso::campo($usuario, $lote), 404);
        $lote->load(['cultivo', 'unidadSuperficie', 'actividades.tipoActividad', 'actividades.ejecutor', 'producciones.unidadMedida']);

        return ['entidad' => 'lote_agricola', 'producto' => [
            'loteid' => (int) $lote->getKey(), 'nombre' => $lote->nombre,
            'codigo_trazabilidad' => $lote->codigo_trazabilidad, 'cultivo' => $lote->cultivo?->nombre,
            'superficie' => (string) $lote->getRawOriginal('superficie'),
            'unidad_superficie' => $lote->unidadSuperficie?->abreviatura ?: $lote->unidadSuperficie?->nombre,
            'ubicacion' => $lote->ubicacion, 'fecha_siembra' => $lote->fechasiembra?->toDateString()],
            'cosechas' => $lote->producciones->sortBy('produccionid')->map(fn ($p) => [
                'produccionid' => (int) $p->getKey(), 'loteid' => (int) $p->loteid,
                'cantidad' => (string) $p->cantidad, 'cantidad_base' => $p->cantidad_base,
                'unidadmedidaid' => $p->unidadmedidaid, 'unidad' => $p->unidadMedida?->abreviatura ?: $p->unidadMedida?->nombre,
                'presentacion_cosecha' => $p->presentacion_cosecha, 'fecha' => $p->fechacosecha?->toDateString(),
            ])->values()->all(),
            'etapas' => $lote->actividades->sortBy([['orden_secuencia', 'asc'], ['actividadid', 'asc']])->map(function ($a) {
                $detalle = json_decode($a->detalle_json ?? '{}', true) ?: [];

                return ['actividadid' => (int) $a->getKey(), 'orden' => $a->orden_secuencia,
                    'proceso' => $a->tipoActividad?->nombre, 'descripcion' => $a->descripcion,
                    'inicio' => $a->fechainicio?->toIso8601String(), 'fin' => $a->fechafin?->toIso8601String(),
                    'responsable_id' => $a->usuarioid_ejecutor, 'responsable' => $a->ejecutor ? trim($a->ejecutor->nombre.' '.$a->ejecutor->apellido) : null,
                    'resultado' => $detalle['cierre']['resultado'] ?? $a->observaciones];
            })->values()->all(), 'materias_primas' => []];
    }

    public function planta(LoteProduccionPedido $lote, Usuario $usuario): array
    {
        abort_unless(CertificadoAcceso::planta($usuario, $lote), 404);
        $lote->load(['pedido', 'unidadMedida', 'plantillaTransformacion',
            'materiasPrimas.insumo.unidadMedida', 'materiasPrimas.materiaPrimaLote.detallePedido.pedido.envioAsignacion',
            'materiasPrimas.materiaPrimaLote.detallePedido.cosechaAlmacen', 'materiasPrimas.presentacionLote',
            'registrosProceso.procesoMaquina.proceso', 'registrosProceso.procesoMaquina.maquina', 'registrosProceso.usuario']);

        return ['entidad' => 'lote_produccion', 'producto' => [
            'loteproduccionpedidoid' => (int) $lote->getKey(), 'codigo_lote' => $lote->codigo_lote,
            'nombre' => $lote->nombre, 'producto' => $lote->producto, 'pedidoid' => $lote->pedidoid,
            'numero_solicitud' => $lote->pedido?->numero_solicitud,
            'plantillatransformacionid' => $lote->plantillatransformacionid,
            'plantilla' => $lote->plantillaTransformacion?->nombre,
            'cantidad_objetivo' => $lote->getRawOriginal('cantidad_objetivo') === null ? null : (string) $lote->getRawOriginal('cantidad_objetivo'),
            'cantidad_producida' => $lote->getRawOriginal('cantidad_producida') === null ? null : (string) $lote->getRawOriginal('cantidad_producida'),
            'unidadmedidaid' => $lote->unidadmedidaid, 'unidad' => $lote->unidadMedida?->abreviatura ?: $lote->unidadMedida?->nombre,
            'fecha_creacion' => $lote->fecha_creacion?->toDateString()],
            'cosechas' => [],
            'materias_primas' => $lote->materiasPrimas->sortBy('loteproduccionmateriaid')->map(function ($m) {
                $partida = $m->materiaPrimaLote;
                $detalle = $partida?->detallePedido;
                $envio = $detalle?->pedido?->envioAsignacion;
                $recibida = collect($envio?->recepcion_planta_datos['lineas'] ?? [])->firstWhere('detallepedidoid', $detalle?->getKey());

                return ['loteproduccionmateriaid' => (int) $m->getKey(), 'insumoid' => $m->insumoid,
                    'nombre' => $m->insumo?->nombre, 'cantidad_planificada' => $m->cantidad_planificada,
                    'cantidad_usada' => $m->cantidad_usada, 'cantidad_unidades_consumidas' => $m->cantidad_unidades_consumidas,
                    'unidadmedidaid' => $m->insumo?->unidadmedidaid, 'unidad' => $m->insumo?->unidadMedida?->abreviatura ?: $m->insumo?->unidadMedida?->nombre,
                    'materiaprimaloteid' => $m->materiaprimaloteid,
                    'inventario_presentacion_loteid' => $m->inventario_presentacion_loteid,
                    'lote_produccion_origen_id' => $m->presentacionLote?->loteproduccionpedidoid,
                    'vencimiento' => $partida?->fecha_vencimiento?->toDateString() ?? $m->presentacionLote?->fecha_vencimiento?->toDateString(),
                    'recepcion' => $detalle ? ['detallepedidoid' => (int) $detalle->getKey(), 'pedidoid' => $detalle->pedidoid,
                        'envioasignacionmultipleid' => $envio?->getKey(), 'fecha' => $envio?->fecha_recepcion_planta?->toIso8601String(),
                        'responsable_id' => $envio?->recepcion_usuarioid, 'linea_recibida' => $recibida,
                        'produccionalmacenamientoid' => $detalle->produccionalmacenamientoid,
                        'produccionid' => $detalle->cosechaAlmacen?->produccionid] : null];
            })->values()->all(),
            'etapas' => $lote->registrosProceso->sortBy([['fecha_registro', 'asc'], ['registroprocesomaquinaplantaid', 'asc']])->map(function ($r) {
                $datos = json_decode($r->variables_ingresadas ?? '{}', true) ?: [];

                return ['registroprocesomaquinaplantaid' => (int) $r->getKey(), 'asignacion_id' => $datos['asignacion_id'] ?? null,
                    'procesomaquinaplantaid' => $r->procesomaquinaplantaid, 'proceso' => $datos['proceso'] ?? $r->procesoMaquina?->proceso?->nombre,
                    'maquina' => $datos['maquina'] ?? $r->procesoMaquina?->maquina?->nombre,
                    'inicio' => $r->hora_inicio?->toIso8601String(), 'fin' => $r->hora_fin?->toIso8601String(),
                    'fecha' => $r->fecha_registro?->toIso8601String(), 'responsable_id' => $r->usuarioid,
                    'responsable' => $r->usuario ? trim($r->usuario->nombre.' '.$r->usuario->apellido) : null,
                    'parametros' => $datos['parametros'] ?? [], 'observaciones' => $r->observaciones];
            })->values()->all()];
    }
}
