@extends('layouts.app')
@section('content_class', 'ag-operacion ag-pedidos-entregas')
@section('title', 'Incidencia #'.$datos['incidenteenvioid'].' | AgroFusion')
@section('page_title', 'Detalle de incidencia')
@section('content')
<x-operacion.encabezado :titulo="'Incidencia #'.$datos['incidenteenvioid']" :descripcion="$datos['tipo']" />
<div class="card mb-3"><div class="card-body"><span class="badge badge-light border mb-3">{{ ucfirst($datos['estado']) }}</span><dl class="row mb-0">
<dt class="col-sm-4 text-muted">Pedido o envío</dt><dd class="col-sm-8">{{ $datos['afectado_referencia'] ?? 'Vínculo no disponible para esta cuenta' }}</dd>
<dt class="col-sm-4 text-muted">Responsable de atención</dt><dd class="col-sm-8">{{ $datos['responsable_nombre'] ?? 'Sin responsable registrado' }}</dd>
<dt class="col-sm-4 text-muted">Autor del reporte</dt><dd class="col-sm-8">{{ $datos['reportado_por']['nombre'] ?? 'No disponible' }}</dd>
<dt class="col-sm-4 text-muted">Fecha de registro</dt><dd class="col-sm-8">{{ $datos['created_at'] ? \Carbon\Carbon::parse($datos['created_at'])->format('d/m/Y H:i') : 'Sin fecha registrada' }}</dd>
</dl></div></div>
<section class="card mb-3"><div class="card-header"><h3 class="card-title">Problema reportado</h3></div><div class="card-body" style="white-space:pre-wrap;overflow-wrap:anywhere">{{ $datos['descripcion'] }}</div></section>
<section class="card mb-3"><div class="card-header"><h3 class="card-title">Seguimiento y solución</h3></div><div class="card-body">
@if($datos['estado'] === 'resuelto')
    <p style="white-space:pre-wrap;overflow-wrap:anywhere">{{ $datos['nota_resolucion'] ?? 'Explicación no registrada en este antecedente histórico.' }}</p><p class="small text-muted mb-0">{{ $datos['fecha_resolucion'] ? \Carbon\Carbon::parse($datos['fecha_resolucion'])->format('d/m/Y H:i') : 'Fecha de resolución no registrada' }} · {{ $datos['resuelto_por']['nombre'] ?? 'Usuario de resolución no disponible' }}</p>
@elseif(in_array($datos['estado'], ['abierto', 'pendiente'], true))
    <p class="text-muted">Pendiente de resolución</p>
    @if($datos['puede_resolver'])<form method="post" action="{{ route('logistica.incidentes.resolve', $datos['incidenteenvioid']) }}">@csrf @method('PATCH')
        <div class="form-group"><label for="nota_resolucion">Explique cómo se solucionó el problema</label><textarea id="nota_resolucion" name="nota_resolucion" class="form-control @error('nota_resolucion') is-invalid @enderror" rows="4" required maxlength="2000">{{ old('nota_resolucion') }}</textarea>@error('nota_resolucion')<div class="invalid-feedback">{{ $message }}</div>@enderror</div><button class="btn btn-success" type="submit">Confirmar resolución</button>
    </form>@endif
@else<p class="mb-0">{{ $datos['estado'] }}</p>@endif
</div></section>
<div class="op-acciones"><a class="btn btn-outline-secondary" href="{{ route('logistica.incidentes.index') }}">Volver a incidencias</a>
@if(in_array($datos['estado'], ['abierto', 'pendiente'], true) && \App\Support\UsuarioRol::puedeOperar(auth()->user()))@can('incidentes.update')<a class="btn btn-outline-secondary" href="{{ route('logistica.incidentes.edit', $datos['incidenteenvioid']) }}">Editar reporte o asignar responsable pendiente</a>@endcan @endif
</div>
@endsection