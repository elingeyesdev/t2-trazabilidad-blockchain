@extends('layouts.app')
@section('content_class', 'ag-operacion ag-pedidos-entregas')
@section('title', 'Editar incidencia | AgroFusion')
@section('page_title', 'Editar incidencia #'.$incidente->getKey())
@section('content')
<div class="card"><div class="card-body"><form method="post" action="{{ route('logistica.incidentes.update', $incidente) }}">@csrf @method('PUT')
<p class="text-muted">El vínculo y la autoría se conservan. La solución se registra únicamente desde el formulario de resolución.</p>
<div class="form-group"><label for="tipo">Tipo</label><input id="tipo" name="tipo" class="form-control" maxlength="100" required value="{{ old('tipo', $incidente->tipo) }}" @readonly((int)$incidente->reportadopor_usuarioid !== (int)auth()->id())>@error('tipo')<div class="text-danger small">{{ $message }}</div>@enderror</div>
<div class="form-group"><label for="descripcion">Descripción original del reporte</label><textarea id="descripcion" name="descripcion" class="form-control" rows="5" maxlength="3000" required @readonly((int)$incidente->reportadopor_usuarioid !== (int)auth()->id())>{{ old('descripcion', $incidente->descripcion) }}</textarea>@error('descripcion')<div class="text-danger small">{{ $message }}</div>@enderror</div>
@if(!$incidente->responsable_usuarioid && $puedeAsignar)<div class="form-group"><label for="responsable_usuarioid">Asignar responsable de atención</label><select id="responsable_usuarioid" name="responsable_usuarioid" class="form-control"><option value="">Seleccione un responsable elegible</option>@foreach($responsables as $r)<option value="{{ $r['usuarioid'] }}" @selected((int)old('responsable_usuarioid') === $r['usuarioid'])>{{ $r['nombre'] }}</option>@endforeach</select>@error('responsable_usuarioid')<div class="text-danger small">{{ $message }}</div>@enderror</div>@else<p>Responsable registrado: {{ $incidente->responsable?->nombre }} {{ $incidente->responsable?->apellido }}</p>@endif
<div class="op-acciones"><button type="submit" class="btn btn-success">Guardar</button><a class="btn btn-outline-secondary" href="{{ route('logistica.incidentes.show', $incidente) }}">Volver al detalle</a></div>
</form></div></div>
@endsection