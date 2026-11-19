@extends('layouts.app')
@section('content_class', 'ag-operacion')
@section('title', 'Movimientos | '.$almacen->nombre)
@section('page_title', 'Movimientos por almacén')
@section('content')
<div class="d-flex flex-wrap justify-content-between align-items-center mb-3"><h2 class="h4">{{ $almacen->nombre }}</h2><a class="btn btn-outline-secondary" href="{{ route($rutaPrefijo.'.existencias.index', $almacen) }}">Ver existencias</a></div>
<div class="card mb-3"><div class="card-body"><form method="GET" class="row align-items-end">
    <div class="col-md-3 form-group"><label for="mov-naturaleza">Naturaleza</label><select name="naturaleza" id="mov-naturaleza" class="form-control"><option value="">Todas</option><option value="ingreso" @selected(request('naturaleza') === 'ingreso')>Entradas</option><option value="salida" @selected(request('naturaleza') === 'salida')>Salidas</option></select></div>
    <div class="col-md-3 form-group"><label for="mov-desde">Desde</label><input type="date" id="mov-desde" name="desde" class="form-control" value="{{ request('desde') }}"></div>
    <div class="col-md-3 form-group"><label for="mov-hasta">Hasta</label><input type="date" id="mov-hasta" name="hasta" class="form-control" value="{{ request('hasta') }}"></div><div class="col-md-3 form-group"><button class="btn btn-success">Filtrar</button></div>
</form></div></div>
<div class="card"><div class="table-responsive"><table class="table mb-0"><thead><tr><th>Fecha / tipo</th><th>Producto / partida</th><th>Cantidad / unidad</th><th>Responsable</th><th>Motivo / referencia</th><th>Saldo antes / después</th></tr></thead><tbody>
@forelse($movimientos as $movimiento)<tr>
    <td class="text-nowrap">{{ $movimiento->fecha?->format('d/m/Y') }}<div class="text-muted small">{{ $movimiento->tipo?->nombre }} · {{ $movimiento->tipo?->naturaleza }}</div></td>
    <td>{{ $movimiento->insumo?->nombre }}<div class="text-muted small">{{ $movimiento->partida?->lote_proveedor ?? $movimiento->presentacionLote?->referencia_lote ?? ($movimiento->materiaprimaloteid ? 'Partida #'.$movimiento->materiaprimaloteid : ($movimiento->inventario_presentacion_loteid ? 'Presentación #'.$movimiento->inventario_presentacion_loteid : 'Sin partida histórica')) }}</div></td>
    <td>{{ \App\Support\CosechaDecimal::mostrar($movimiento->cantidad) }} {{ $movimiento->unidadMedida?->abreviatura }}@unless($movimiento->unidadmedidaid)<div class="text-muted small">Unidad histórica sin registrar</div>@endunless</td>
    <td>{{ $movimiento->usuario?->nombre ?? 'Sin responsable histórico' }} {{ $movimiento->usuario?->apellido }}</td>
    <td>{{ $movimiento->destino_motivo }}<div class="text-muted small">{{ $movimiento->referencia }}</div></td>
    <td><div>Antes: <x-operacion.cantidad :valor="$movimiento->saldo_anterior" :unidad="$movimiento->unidadMedida?->abreviatura ?? $movimiento->unidadMedida?->nombre" /></div><div>Después: <x-operacion.cantidad :valor="$movimiento->saldo_posterior" :unidad="$movimiento->unidadMedida?->abreviatura ?? $movimiento->unidadMedida?->nombre" /></div></td>
</tr>@empty<tr><td colspan="6" class="text-center text-muted py-4">No hay movimientos para estos filtros.</td></tr>@endforelse
</tbody></table></div><div class="card-footer">{{ $movimientos->links() }}</div></div>
@endsection
