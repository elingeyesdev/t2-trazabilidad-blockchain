@if(\App\Support\ActividadPermisos::puedeReasignar(auth()->user(), $actividad))
<div class="d-flex flex-wrap align-items-start gap-2 mb-3">
    <a href="{{ route('actividades.edit', $actividad) }}" class="btn btn-outline-secondary btn-sm">Reasignar actividad</a>
    @if(\App\Support\ActividadPermisos::puedeCancelarPreparacion(auth()->user(), $actividad))
    <form method="POST" action="{{ route('actividades.cancelar-preparacion', $actividad) }}" class="border rounded p-3">
        @csrf
        <p class="small text-secondary mb-2">La siembra ya está realizada. Puede cancelar esta preparación pendiente para liberar el turno, conservando su historial.</p>
        <label class="form-label" for="motivo-cancelar-{{ $actividad->actividadid }}">Motivo de cancelación</label>
        <input class="form-control form-control-sm mb-2" id="motivo-cancelar-{{ $actividad->actividadid }}" name="motivo" required maxlength="500">
        <button class="btn btn-outline-danger btn-sm" type="submit">Cancelar preparación incompatible</button>
    </form>
    @endif
</div>
@endif
