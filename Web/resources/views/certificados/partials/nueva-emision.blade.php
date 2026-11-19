@php($puedeEmitir = $ambito === 'campo' ? \App\Support\UsuarioRol::gestionaCampo(auth()->user()) && auth()->user()->can('certificaciones.create') : \App\Support\UsuarioRol::gestionaPlanta(auth()->user()) && auth()->user()->can('lote_produccion.update'))
@if($puedeEmitir)
<details class="card mt-3" @if($errors->any()) open @endif><summary class="card-header">Registrar una nueva emisión</summary><div class="card-body">
@if($errors->any())<div class="alert alert-danger"><ul class="mb-0">@foreach($errors->all() as $error)<li>{{ $error }}</li>@endforeach</ul></div>@endif
<p class="text-muted small">Se conservarán las emisiones anteriores. El servidor comprobará los requisitos actuales del lote.</p>
<form method="POST" action="{{ $ambito === 'campo' ? route('certificaciones.store') : route('procesamiento.certificar', $producto) }}">
    @csrf
    <input type="hidden" name="solicitud_id" value="{{ old('solicitud_id', (string) \Illuminate\Support\Str::uuid()) }}">
    @if($ambito === 'campo')<input type="hidden" name="loteid" value="{{ $producto->getKey() }}">@endif
    <label>Resultado<select class="form-control mb-3" name="{{ $ambito === 'campo' ? 'resultado' : 'razon' }}"><option @selected(old($ambito === 'campo' ? 'resultado' : 'razon', 'Certificado') === 'Certificado')>Certificado</option><option @selected(old($ambito === 'campo' ? 'resultado' : 'razon') === 'No conforme')>No conforme</option></select></label>
    <div class="form-group"><label for="emision-observaciones">Observaciones</label><textarea id="emision-observaciones" class="form-control" name="observaciones" maxlength="{{ $ambito === 'campo' ? 1000 : 500 }}">{{ old('observaciones') }}</textarea></div>
    <div class="form-group"><label for="emision-recomendaciones">Recomendaciones</label><textarea id="emision-recomendaciones" class="form-control" name="recomendaciones" maxlength="2000">{{ old('recomendaciones') }}</textarea></div>
    <button class="btn btn-success" type="submit">Emitir nuevo certificado</button>
</form></div></details>
@endif
