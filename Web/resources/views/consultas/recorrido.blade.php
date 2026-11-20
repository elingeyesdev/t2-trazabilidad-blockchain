@extends('layouts.app')
@section('content_class', 'ag-operacion ag-pedidos-entregas')
@section('title', 'Recorrido e indicadores | AgroFusion')
@section('page_title', 'Recorrido e indicadores')
@section('content')
<x-operacion.encabezado titulo="Recorrido e indicadores" descripcion="Consulte una cosecha o un lote de planta concreto, sus tareas pendientes y las existencias bajas de su ámbito." />
@if($errors->any())
    <div class="alert alert-danger">{{ $errors->first() }}</div>
@endif
<form method="get" class="card mb-3"><div class="card-body">
    <div class="row">
        <div class="col-sm-6 col-lg-2 form-group"><label for="desde">Desde</label><input id="desde" class="form-control" type="date" name="desde" value="{{ request('desde') }}"></div>
        <div class="col-sm-6 col-lg-2 form-group"><label for="hasta">Hasta</label><input id="hasta" class="form-control" type="date" name="hasta" value="{{ request('hasta') }}"></div>
        <div class="col-lg-3 form-group"><label for="almacenid">Almacén autorizado</label><select id="almacenid" class="form-control" name="almacenid"><option value="">Todos los autorizados</option>@foreach($almacenes as $a)<option value="{{ $a['almacenid'] }}" @selected((int)request('almacenid') === $a['almacenid'])>{{ $a['nombre'] }}</option>@endforeach</select></div>
        <div class="col-sm-6 col-lg-2 form-group"><label for="tipo">Tipo de partida</label><select id="tipo" class="form-control" name="tipo"><option value="">Sin selección</option><option value="cosecha" @selected(request('tipo') === 'cosecha')>Cosecha</option><option value="planta" @selected(request('tipo') === 'planta')>Lote de planta</option></select></div>
        <div class="col-sm-6 col-lg-3 form-group"><label for="partida">Identificador de la partida</label><input id="partida" type="number" min="1" name="partida" value="{{ request('partida') }}" class="form-control" placeholder="ID del detalle de cosecha o lote"></div>
    </div>
    <div class="op-acciones"><button class="btn btn-success" type="submit">Consultar</button><a class="btn btn-outline-secondary" href="{{ route('consulta-recorrido') }}">Limpiar</a></div>
    <p class="text-muted small mt-3 mb-0">Intervalo inclusivo en {{ $alcance['zona_horaria'] }}. Complete ambas fechas para limitar el periodo. Las existencias son actuales: el filtro de fecha no aplica.</p>
</div></form>
<div class="row">
    <div class="col-md-6"><div class="card mb-3"><div class="card-body"><div class="text-muted">Tareas pendientes del ámbito consultado</div><div class="h2 mb-0">{{ $indicadores['tareas_pendientes'] ?? 'Sin permiso de consulta' }}</div></div></div></div>
    <div class="col-md-6"><div class="card mb-3"><div class="card-body"><div class="text-muted">Registros producto–almacén con existencias bajas</div><div class="h2 mb-0">{{ $indicadores['registros_producto_almacen_bajos'] ?? 'Sin permiso de consulta' }}</div></div></div></div>
</div>
<section class="card mb-3"><div class="card-header"><h3 class="card-title">Recorrido de la partida</h3></div><div class="card-body">
    @if(!$recorrido)
        <p class="text-muted mb-0">Seleccione una cosecha o un lote de planta. Los productos de catálogo no se agrupan como si fueran una misma partida.</p>
    @else
        <p><strong>{{ $recorrido['entidad']['tipo'] === 'planta' ? 'Lote de planta' : 'Cosecha' }} #{{ $recorrido['entidad']['id'] }}</strong> · {{ $recorrido['coincidencias'] }} elementos coinciden con los filtros.</p>
        <p class="small text-muted">{{ $recorrido['criterio'] }}</p>
        @foreach(($recorrido['antecedentes']['restricciones'] ?? []) as $seccion => $restriccion)
            @if($restriccion)<p class="small text-muted">Información parcial según los permisos de esta cuenta.</p>@break @endif
        @endforeach
        @forelse($recorrido['elementos'] as $elemento)
            <article class="border rounded p-3 mb-2">
                <div class="d-flex flex-wrap justify-content-between"><strong>{{ ucfirst(str_replace('_', ' ', $elemento['tipo'])) }} #{{ $elemento['id'] }}</strong><span class="text-muted small">{{ $elemento['coincide_filtros'] ? 'Coincide con la consulta' : 'Contexto relacionado' }}</span></div>
                <p class="text-muted small mb-2">{{ $elemento['fecha'] ?? 'Fecha no registrada' }} · {{ $elemento['almacenid'] ? 'Almacén #'.$elemento['almacenid'] : 'Sin relación directa con un almacén' }}{{ !$elemento['fecha_filtro_aplica'] ? ' · Fecha no aplica: saldo actual' : '' }}</p>
                @include('consultas.partials.elemento', ['datos' => $elemento['datos']])
            </article>
        @empty<p class="text-muted">Sin vínculos registrados disponibles para esta cuenta.</p>@endforelse
        @if(!$recorrido['coincidencias'])<p class="text-muted mb-0">Sin coincidencias para el intervalo; se conserva el contexto autorizado.</p>@endif
        @if($recorrido['emisiones_historicas'])
            <div class="mt-3"><strong>Antecedentes de certificados</strong><p class="small text-muted">Referencias conservadas; no se recalculan con los filtros de esta consulta.</p>
            @foreach($recorrido['emisiones_historicas'] as $emision)<p class="small mb-1">Emisión #{{ $emision['id'] }} · {{ $emision['codigo'] ?? 'Código no registrado' }} · {{ $emision['fecha'] ?? 'Fecha no registrada' }}</p>@endforeach</div>
        @endif
    @endif
</div></section>
<section class="card mb-3"><div class="card-header"><h3 class="card-title">Tareas pendientes</h3></div>
    <div class="card-body small text-muted">{{ $alcance['pendientes'] }}</div>
    <div class="table-responsive"><table class="table op-tabla-movil mb-0"><thead><tr><th>Tarea</th><th>Responsable</th><th>Fecha</th><th>Estado / vínculo</th></tr></thead><tbody>
        @forelse($pendientes as $t)<tr><td data-label="Tarea">{{ $t['descripcion'] ?? 'Sin descripción' }}<small class="d-block text-muted">{{ str_replace('_', ' ', $t['tipo']) }} #{{ $t['id'] }}</small></td><td data-label="Responsable">{{ isset($t['responsable_id']) ? '#'.$t['responsable_id'] : 'Sin asignación registrada' }}</td><td data-label="Fecha">{{ $t['fecha'] ?? 'Sin fecha registrada' }}<small class="d-block text-muted">{{ $t['significado_fecha'] }}</small></td><td data-label="Estado / vínculo">Pendiente · {{ isset($t['loteid']) ? 'Lote agrícola #'.$t['loteid'] : 'Lote de planta #'.$t['loteproduccionpedidoid'] }}</td></tr>
        @empty<tr><td colspan="4" class="op-vacio">{{ $indicadores['tareas_pendientes'] === null ? 'Sin permiso de consulta.' : 'Sin tareas pendientes para estos filtros.' }}</td></tr>@endforelse
    </tbody></table></div><div class="card-footer">{{ $pendientes->links() }}</div>
</section>
<section class="card mb-3"><div class="card-header"><h3 class="card-title">Existencias bajas actuales</h3></div><div class="card-body small text-muted">{{ $alcance['existencias_bajas'] }}</div>
    <div class="table-responsive"><table class="table op-tabla-movil mb-0"><thead><tr><th>Producto / almacén</th><th>Disponible</th><th>Mínimo</th><th>Reservado / vencido / bloqueado</th></tr></thead><tbody>
        @forelse($existencias_bajas as $b)<tr><td data-label="Producto / almacén">{{ $b['nombre'] }}<small class="d-block text-muted">{{ $b['almacen'] }}</small></td><td data-label="Disponible"><x-operacion.cantidad :valor="$b['cantidad_disponible']" :unidad="$b['unidad']" /></td><td data-label="Mínimo"><x-operacion.cantidad :valor="$b['minimo']" :unidad="$b['unidad']" /></td><td data-label="Reservado / vencido / bloqueado">{{ $b['cantidad_reservada'] }} / {{ $b['cantidad_vencida'] }} / {{ $b['cantidad_bloqueada'] }} {{ $b['unidad'] ?? 'Unidad no registrada' }}@if(!$b['saldo_coherente'])<small class="d-block">Revisar desglose de partidas.</small>@endif</td></tr>
        @empty<tr><td colspan="4" class="op-vacio">{{ $indicadores['registros_producto_almacen_bajos'] === null ? 'Sin permiso de consulta.' : 'Sin alertas de existencias bajas para estos almacenes.' }}</td></tr>@endforelse
    </tbody></table></div><div class="card-footer">{{ $existencias_bajas->links() }}</div>
</section>
<p class="text-muted small">{{ $alcance['consistencia'] }}</p>
@endsection
