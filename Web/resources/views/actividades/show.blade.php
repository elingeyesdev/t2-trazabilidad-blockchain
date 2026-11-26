@extends('layouts.tabler-lotes')
@section('title', 'Detalle de actividad | AgroFusion')
@section('header')<h1 class="page-title">Detalle de actividad</h1>@endsection
@section('content')
@php($completada = $actividad->fechafin !== null)
<div class="card">
 <div class="card-header justify-content-between gap-2 flex-wrap">
  <h2 class="card-title">{{ $actividad->descripcion ?: ($actividad->tipoActividad?->nombre ?? 'Actividad') }}</h2>
  <span class="badge {{ $completada ? 'bg-success-lt' : 'bg-warning-lt' }}">{{ $actividad->cancelada_en ? 'Cancelada' : ($completada ? 'Completada' : 'Pendiente') }}</span>
 </div>
 <div class="card-body">
  @include('actividades.partials.gestion-pendiente', ['actividad' => $actividad])
  @if($actividad->cancelada_en)
   <div class="alert alert-secondary">Cancelada el {{ $actividad->cancelada_en->format('d/m/Y H:i') }} por usuario #{{ $actividad->cancelada_por_usuarioid }}. Motivo: {{ $actividad->motivo_cancelacion }}</div>
  @endif
  @php($reasignaciones = (json_decode($actividad->detalle_json ?? '', true) ?: [])['historial_asignaciones'] ?? [])
  @if($reasignaciones)
   <h3 class="h4">Historial de asignación</h3>
   <ul>@foreach($reasignaciones as $cambio)<li>{{ $cambio['fecha'] }}: usuario #{{ $cambio['anterior_usuarioid'] }} → #{{ $cambio['nuevo_usuarioid'] }}, por usuario #{{ $cambio['por_usuarioid'] }}.</li>@endforeach</ul>
  @endif
  <dl class="row">
   <dt class="col-sm-4">Lote</dt><dd class="col-sm-8">{{ $actividad->lote?->nombre }}</dd>
   <dt class="col-sm-4">Tipo</dt><dd class="col-sm-8">{{ $actividad->tipoActividad?->nombre }}</dd>
   <dt class="col-sm-4">Trabajador asignado</dt><dd class="col-sm-8">{{ trim(($actividad->usuario?->nombre ?? '').' '.($actividad->usuario?->apellido ?? '')) ?: 'Sin asignación' }}</dd>
   <dt class="col-sm-4">Responsable del cierre</dt><dd class="col-sm-8">{{ $completada ? (trim(($actividad->ejecutor?->nombre ?? '').' '.($actividad->ejecutor?->apellido ?? '')) ?: 'No registrado') : 'Pendiente de ejecución' }}</dd>
   <dt class="col-sm-4">Fecha de cierre</dt><dd class="col-sm-8">{{ $actividad->fechafin?->format('d/m/Y H:i') ?? 'Pendiente de ejecución' }}</dd>
  </dl>
  @if($consulta['resultado'])<h3 class="h4">Resultado</h3><p class="text-break">{{ $consulta['resultado'] }}</p>@endif
  @if($actividad->observaciones)<h3 class="h4">Observaciones de planificación</h3><p class="text-break">{{ $actividad->observaciones }}</p>@endif
  <h3 class="h4">Fotografía de la actividad</h3>
  @if($consulta['evidencia_estado'] === 'disponible')
   <a href="{{ $consulta['evidencia_foto_url'] }}" target="_blank" rel="noopener" aria-label="Abrir fotografía de esta actividad">
    <img src="{{ $consulta['evidencia_foto_url'] }}" alt="Fotografía del trabajo realizado: {{ $actividad->descripcion }}" class="img-fluid rounded border mb-2" style="max-height: 420px; object-fit: contain;" id="fotoActividad">
   </a>
   <p class="small text-secondary" id="estadoFotoActividad">Selecciona la fotografía para ampliarla.</p>
  @elseif($consulta['evidencia_estado'] === 'no_disponible')
   <p class="text-warning">Esta actividad tiene una fotografía registrada, pero el archivo no está disponible.</p>
  @else
   <p class="text-secondary">Esta actividad no tiene fotografía registrada</p>
  @endif
  <h3 class="h4 mt-4">Insumos utilizados</h3>
  @if($consulta['consumos'] !== [])
   <div class="table-responsive"><table class="table table-vcenter">
    <thead><tr><th>Insumo</th><th>Cantidad</th><th>Unidad</th><th>Almacén de origen</th></tr></thead>
    <tbody>@foreach($consulta['consumos'] as $fila)
     <tr><td>{{ $fila['nombre'] ?? 'Nombre no registrado' }} <small class="text-secondary">#{{ $fila['insumoid'] }}</small></td>
      <td>{{ $fila['cantidad'] }}</td><td>{{ $fila['unidad'] ?? 'No registrada' }}@if(!$fila['unidad_historica'])<small class="d-block text-secondary">Catálogo actual; unidad histórica no registrada</small>@endif</td>
      <td>{{ $fila['almacenid'] !== null ? '#'.$fila['almacenid'] : 'No registrado' }}</td></tr>
    @endforeach</tbody>
   </table></div>
  @else
   <p class="text-secondary">Esta actividad no registra consumo de insumos</p>
  @endif
 </div>
 <div class="card-footer d-flex gap-2 flex-wrap">
  <a href="{{ route('actividades.index') }}" class="btn btn-outline-secondary">Volver a actividades</a>
  <a href="{{ route('lotes.trazabilidad', $actividad->loteid) }}" class="btn btn-outline-primary">Ver lote</a>
 </div>
</div>
@endsection
@push('scripts')
<script>
document.getElementById('fotoActividad')?.addEventListener('error', function () {
 this.hidden = true;
 document.getElementById('estadoFotoActividad').textContent = 'La fotografía registrada no pudo cargarse. Vuelve a intentar abrirla.';
});
</script>
@endpush
