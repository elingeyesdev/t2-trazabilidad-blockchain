@extends('layouts.tabler-lotes')
@section('title', 'Detalle de actividad | AgroFusion')
@section('header')<h1 class="page-title">Detalle de actividad</h1>@endsection
@section('content')
@php($completada = $actividad->fechafin !== null)
@if(session('success'))
 <div class="alert alert-success">{{ session('success') }}</div>
@endif
@if(session('info'))
 <div class="alert alert-info">{{ session('info') }}</div>
@endif
@if(session('error'))
 <div class="alert alert-danger">{{ session('error') }}</div>
@endif
@if($errors->any())
 <div class="alert alert-danger">
  <ul class="mb-0 ps-3">
   @foreach($errors->all() as $err)
    <li>{{ $err }}</li>
   @endforeach
  </ul>
 </div>
@endif

<div class="card mb-3">
 <div class="card-header justify-content-between gap-2 flex-wrap">
  <h2 class="card-title">{{ $actividad->descripcion ?: ($actividad->tipoActividad?->nombre ?? 'Actividad') }}</h2>
  <span class="badge {{ $completada ? 'bg-success-lt' : 'bg-warning-lt' }}">{{ $completada ? 'Completada' : 'Pendiente' }}</span>
 </div>
 <div class="card-body">
  <dl class="row">
   <dt class="col-sm-4">Lote</dt><dd class="col-sm-8">{{ $actividad->lote?->nombre }}</dd>
   <dt class="col-sm-4">Tipo</dt><dd class="col-sm-8">{{ $actividad->tipoActividad?->nombre }}</dd>
   <dt class="col-sm-4">Trabajador asignado</dt><dd class="col-sm-8">{{ trim(($actividad->usuario?->nombre ?? '').' '.($actividad->usuario?->apellido ?? '')) ?: 'Sin asignación' }}</dd>
   <dt class="col-sm-4">Responsable del cierre</dt><dd class="col-sm-8">{{ $completada ? (trim(($actividad->ejecutor?->nombre ?? '').' '.($actividad->ejecutor?->apellido ?? '')) ?: 'No registrado') : 'Pendiente de ejecución' }}</dd>
   <dt class="col-sm-4">Fecha de cierre</dt><dd class="col-sm-8">{{ $actividad->fechafin?->format('d/m/Y H:i') ?? 'Pendiente de ejecución' }}</dd>
  </dl>

  @if(!$completada && !empty($puedeReasignar))
  <div class="border rounded p-3 mb-4 bg-light">
   <h3 class="h4 mb-2"><i class="ti ti-user-edit me-1"></i> Cambiar responsable</h3>
   <p class="small text-secondary mb-2">Puedes reasignar esta actividad a cualquier trabajador de tu equipo o a ti mismo mientras no haya sido completada.</p>
   <form method="POST" action="{{ route('actividades.reasignar-responsable', $actividad) }}" class="d-flex flex-wrap align-items-center gap-2">
    @csrf
    @method('PATCH')
    <select name="usuarioid" class="form-select w-auto" required aria-label="Nuevo responsable">
     @foreach($responsablesDisponibles ?? [] as $resp)
      <option value="{{ $resp->usuarioid }}" @selected((int) old('usuarioid', $actividad->usuarioid) === (int) $resp->usuarioid)>
       {{ trim($resp->nombre.' '.($resp->apellido ?? '')) }}{{ (int) $resp->usuarioid === (int) auth()->id() ? ' (Yo — Jefe agrícola)' : '' }}
      </option>
     @endforeach
    </select>
    <button type="submit" class="btn btn-outline-primary">
     <i class="ti ti-check me-1"></i> Guardar responsable
    </button>
   </form>
  </div>
  @endif

  @if(!$completada && !empty($puedeCerrar))
  <div class="border border-primary rounded p-3 mb-4" id="cerrar-actividad">
   <h3 class="h4 text-primary mb-2"><i class="ti ti-camera me-1"></i> Completar y cerrar actividad</h3>
   <p class="small text-secondary mb-3">Registra el resultado del trabajo y sube una fotografía de evidencia para cerrar la actividad y avanzar el estado del lote.</p>
   <form method="POST" action="{{ route('actividades.marcar-realizada', $actividad) }}" enctype="multipart/form-data">
    @csrf
    <div class="mb-3">
     <label class="form-label fw-semibold" for="resultadoCierre">Resultado de la actividad <span class="text-danger">*</span></label>
     <textarea name="resultado" id="resultadoCierre" class="form-control @error('resultado') is-invalid @enderror" rows="2" maxlength="250" required placeholder="Ej: Siembra completada en los surcos planificados con buena humedad.">{{ old('resultado') }}</textarea>
     @error('resultado')<div class="invalid-feedback">{{ $message }}</div>@enderror
    </div>
    <div class="mb-3">
     <label class="form-label fw-semibold" for="evidenciaFotoCierre">Fotografía de evidencia <span class="text-danger">*</span></label>
     <input type="file" name="evidencia_foto" id="evidenciaFotoCierre" class="form-control @error('evidencia_foto') is-invalid @enderror" accept="image/jpeg,image/png,image/webp" required>
     <small class="form-hint">Formatos permitidos: JPG, PNG o WebP (máx. 5 MB).</small>
     @error('evidencia_foto')<div class="invalid-feedback">{{ $message }}</div>@enderror
    </div>
    @php($insumosPlanificados = $consulta['insumos_planificados'] ?? [])
    @if(!empty($semillaFijada) && !empty($almacenLote))
    <div class="mb-3">
     <label class="form-label fw-semibold">
      <i class="ti ti-lock me-1"></i> Semilla planificada del lote
     </label>
     <div class="row g-2">
      <div class="col-md-7">
       <input type="hidden" name="consumos[0][almacenid]" value="{{ $semillaFijada->almacenid ?? $almacenLote->almacenid }}">
       <input type="hidden" name="consumos[0][insumoid]" value="{{ $semillaFijada->insumoid }}">
       <input type="text" class="form-control bg-light" readonly
              value="{{ $semillaFijada->nombre }} (stock: {{ rtrim(rtrim((string) $semillaFijada->stock, '0'), '.') }} {{ $semillaFijada->unidadMedida->abreviatura ?? $semillaFijada->unidadMedida->nombre ?? '' }})">
      </div>
      <div class="col-md-5">
       <input type="number" step="0.001" min="0.001" name="consumos[0][cantidad]" class="form-control" required
              placeholder="Cantidad consumida"
              value="{{ old('consumos.0.cantidad', $actividad->lote?->getRawOriginal('cantidad_semilla_planificada')) }}">
      </div>
     </div>
     <small class="form-hint">Esta semilla fue definida al crear el lote y no puede cambiarse; solo confirma la cantidad real sembrada.</small>
    </div>
    @elseif(!empty($insumosPlanificados) && !empty($almacenLote))
    <div class="mb-3">
     <label class="form-label fw-semibold">
      <i class="ti ti-lock me-1"></i> Insumo(s) asignado(s) para esta actividad
     </label>
     @foreach($insumosPlanificados as $idxPlan => $plan)
      <div class="row g-2 mb-2">
       <div class="col-md-7">
        <input type="hidden" name="consumos[{{ $idxPlan }}][almacenid]" value="{{ $plan['almacenid'] ?? $almacenLote->almacenid }}">
        <input type="hidden" name="consumos[{{ $idxPlan }}][insumoid]" value="{{ $plan['insumoid'] }}">
        <input type="text" class="form-control bg-light" readonly
               value="{{ $plan['nombre'] ?? ('Insumo #'.$plan['insumoid']) }}{{ !empty($plan['unidad']) ? ' ('.$plan['unidad'].')' : '' }}">
       </div>
       <div class="col-md-5">
        <input type="number" step="0.001" min="0.001" name="consumos[{{ $idxPlan }}][cantidad]" class="form-control" required
               placeholder="Cantidad consumida"
               value="{{ old('consumos.'.$idxPlan.'.cantidad', $plan['cantidad']) }}">
       </div>
      </div>
     @endforeach
     <small class="form-hint">Asignado al programar la actividad; solo confirma la cantidad real utilizada.</small>
    </div>
    @elseif(!empty($requiereInsumos))
     @if(!empty($almacenLote) && ($insumosDisponibles ?? collect())->isNotEmpty())
     <div class="mb-3">
      <label class="form-label fw-semibold">
       Insumo utilizado <span class="text-danger">*</span>
      </label>
      <div class="row g-2">
       <div class="col-md-7">
        <input type="hidden" name="consumos[0][almacenid]" value="{{ $almacenLote->almacenid }}" id="consumoAlmacen0" disabled>
        <select name="consumos[0][insumoid]" id="consumoInsumo0" class="form-select" required>
         <option value="">Selecciona un insumo de tu almacén…</option>
         @foreach($insumosDisponibles as $ins)
          <option value="{{ $ins->insumoid }}" @selected((string) old('consumos.0.insumoid') === (string) $ins->insumoid)>
           {{ $ins->nombre }} (stock: {{ rtrim(rtrim((string) $ins->stock, '0'), '.') }} {{ $ins->unidadMedida->abreviatura ?? $ins->unidadMedida->nombre ?? '' }})
          </option>
         @endforeach
        </select>
       </div>
       <div class="col-md-5">
        <input type="number" step="0.001" min="0.001" name="consumos[0][cantidad]" id="consumoCantidad0" class="form-control" placeholder="Cantidad consumida" value="{{ old('consumos.0.cantidad') }}" disabled>
       </div>
      </div>
     </div>
     @else
     <div class="alert alert-warning small mb-3">
      <i class="ti ti-alert-triangle me-1"></i>
      Esta actividad requiere registrar un insumo con stock disponible en tu almacén agrícola. Carga existencias en <strong>Inventario</strong> antes de cerrarla.
     </div>
     @endif
    @endif
    <button type="submit" class="btn btn-primary">
     <i class="ti ti-send me-1"></i> Enviar evidencia y cerrar actividad
    </button>
   </form>
  </div>
  @elseif(!$completada && !empty($puedeReasignar))
  <div class="alert alert-info mb-4">
   <i class="ti ti-info-circle me-1"></i>
   @if(empty($esEnTurno))
    Esta actividad está en espera de que se complete una actividad anterior del mismo lote.
   @else
    Solo el responsable asignado (<strong>{{ trim(($actividad->usuario?->nombre ?? '').' '.($actividad->usuario?->apellido ?? '')) ?: 'sin asignar' }}</strong>) puede cerrarla con evidencia fotográfica. Si necesitas cerrarla tú o pasarla a otro trabajador, cambia el responsable arriba.
   @endif
  </div>
  @endif

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
  @if(!$completada && !empty($puedeReasignar))
   <a href="{{ route('actividades.edit', $actividad) }}" class="btn btn-outline-secondary">Editar planificación</a>
  @endif
 </div>
</div>
@endsection
@push('scripts')
<script>
document.getElementById('fotoActividad')?.addEventListener('error', function () {
 this.hidden = true;
 document.getElementById('estadoFotoActividad').textContent = 'La fotografía registrada no pudo cargarse. Vuelve a intentar abrirla.';
});
(function () {
 var insSel = document.getElementById('consumoInsumo0');
 var almInp = document.getElementById('consumoAlmacen0');
 var cantInp = document.getElementById('consumoCantidad0');
 if (!insSel || !almInp || !cantInp) return;
 function syncConsumo() {
  var activo = insSel.value !== '';
  almInp.disabled = !activo;
  cantInp.disabled = !activo;
  cantInp.required = activo;
  if (!activo) cantInp.value = '';
 }
 insSel.addEventListener('change', syncConsumo);
 syncConsumo();
})();
</script>
@endpush