@extends('layouts.app')
@section('content_class', 'ag-operacion ag-pedidos-entregas')
@section('title', 'Incidencias | AgroFusion')
@section('page_title', 'Incidencias de pedidos y envíos')
@section('content')
<x-operacion.encabezado titulo="Incidencias" descripcion="Consulte los problemas reportados, el responsable de atención y su solución registrada." />
<form method="get" class="card mb-3"><div class="card-body"><div class="row">
    <div class="col-md-6 form-group"><label for="q">Buscar descripción, tipo o solución</label><input id="q" name="q" maxlength="150" class="form-control" value="{{ request('q') }}"></div>
    <div class="col-md-4 form-group"><label for="estado">Estado</label><select id="estado" name="estado" class="form-control"><option value="">Todos los estados</option>@foreach(['abierto' => 'Abierto', 'pendiente' => 'Pendiente', 'resuelto' => 'Resuelto'] as $v => $texto)<option value="{{ $v }}" @selected(request('estado') === $v)>{{ $texto }}</option>@endforeach</select>@error('estado')<div class="text-danger small">{{ $message }}</div>@enderror</div>
</div>
@foreach(['afectado_tipo', 'afectado_id'] as $campo)@if(request()->filled($campo))<input type="hidden" name="{{ $campo }}" value="{{ request($campo) }}">@endif @endforeach
<div class="op-acciones"><button class="btn btn-success" type="submit">Filtrar</button><a class="btn btn-outline-secondary" href="{{ route('logistica.incidentes.index') }}">Limpiar</a>@can('incidentes.create')<a class="btn btn-outline-success" href="{{ route('logistica.incidentes.create', request()->only(['afectado_tipo', 'afectado_id'])) }}">Registrar incidencia</a>@endcan</div>
</div></form>
<div class="card"><div class="card-header"><h3 class="card-title">{{ $incidentes->total() }} incidencias en esta consulta</h3></div>
<div class="table-responsive"><table class="table op-tabla-movil mb-0"><thead><tr><th>Incidencia</th><th>Pedido o envío</th><th>Responsable</th><th>Estado</th><th>Acción</th></tr></thead><tbody>
@forelse($incidentes as $i)<tr><td data-label="Incidencia"><strong>#{{ $i['incidenteenvioid'] }} · {{ $i['tipo'] }}</strong><span class="d-block">{{ \Illuminate\Support\Str::limit($i['descripcion'], 120) }}</span><small class="text-muted">{{ $i['created_at'] ? \Carbon\Carbon::parse($i['created_at'])->format('d/m/Y H:i') : 'Fecha no registrada' }}</small></td><td data-label="Pedido o envío">{{ $i['afectado_referencia'] ?? 'Vínculo no disponible' }}</td><td data-label="Responsable">{{ $i['responsable_nombre'] ?? 'Sin responsable registrado' }}</td><td data-label="Estado"><span class="badge badge-light border">{{ ucfirst($i['estado']) }}</span><small class="d-block text-muted">{{ $i['seguimiento'] }}</small></td><td data-label="Acción"><a class="btn btn-outline-secondary btn-sm" href="{{ route('logistica.incidentes.show', $i['incidenteenvioid']) }}">Consultar</a></td></tr>
@empty<tr><td colspan="5" class="op-vacio">No hay incidencias disponibles para su cuenta con estos filtros.</td></tr>@endforelse
</tbody></table></div><div class="card-footer">{{ $incidentes->links() }}</div></div>
@endsection