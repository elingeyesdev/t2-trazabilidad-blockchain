@php
    $pedido = $asignacion->pedido;
    $tieneChofer = (bool) $asignacion->transportista_usuarioid;
@endphp

@if($pedido && in_array('aceptar', app(\App\Services\PedidoTransicionService::class)->accionesDisponibles($pedido, auth()->user()), true))
<div class="env-decision-agricola mb-3">
    <div class="env-decision-head">
        <span class="env-decision-icon"><i class="fas fa-seedling"></i></span>
        <div>
            <strong class="d-block">Aprobación agrícola pendiente</strong>
            <span class="small text-muted">Descuenta las cantidades del origen agrícola para habilitar la salida del camión.</span>
        </div>
    </div>

    @if(($erroresStock ?? []) !== [])
        <div class="alert alert-danger py-2 px-3 small mb-3 border-0">
            <strong><i class="fas fa-exclamation-triangle mr-1"></i>Stock insuficiente:</strong>
            <ul class="mb-0 pl-3 mt-1">
                @foreach($erroresStock as $error)
                    <li>{{ $error }}</li>
                @endforeach
            </ul>
        </div>
    @endif

    <div class="env-paso-mini mb-2">
        <span class="env-paso-num">1</span>
        <span>Aceptar y descontar material del origen agrícola.</span>
    </div>
    @if($tieneChofer)
        <div class="env-paso-mini mb-3">
            <span class="env-paso-num env-paso-num--blue">2</span>
            <span>El chofer <strong>{{ trim(($asignacion->transportista?->nombre ?? '').' '.($asignacion->transportista?->apellido ?? '')) }}</strong> podrá empezar ruta al salir cargado.</span>
        </div>
    @endif

    <form data-pedido-decision method="POST" action="{{ route('logistica.asignaciones.aceptar-pedido', $asignacion) }}" class="mb-2">
        @csrf
        <button type="button" class="btn btn-success btn-block font-weight-bold"
                @disabled(($erroresStock ?? []) !== [])
                data-confirm-modal
                data-confirm-tone="success"
                data-confirm-title="Confirmar aceptación del envío"
                data-confirm-message="¿Aceptar este pedido? Se descontarán las cantidades del origen agrícola.">
            <i class="fas fa-check-circle mr-1"></i> Aceptar pedido
        </button>
    </form>

    <details class="env-rechazo-details" @if($errors->has('motivo_rechazo') || old('motivo_rechazo')) open @endif>
        <summary class="small text-muted" style="cursor:pointer;">Rechazar solicitud</summary>
        <form data-pedido-decision method="POST" action="{{ route('logistica.asignaciones.rechazar-pedido', $asignacion) }}" class="mt-2">
            @csrf
            <div class="form-group mb-2">
                <label class="small text-muted mb-1">Motivo del rechazo (obligatorio)</label>
                <textarea required aria-label="Motivo del rechazo" name="motivo_rechazo" class="form-control form-control-sm" rows="2" maxlength="500" placeholder="Indique por qué no puede atenderse">{{ old('motivo_rechazo') }}</textarea>
                            @error('motivo_rechazo')<span class="text-danger small d-block">{{ $message }}</span>@enderror
            </div>
            <button type="button" class="btn btn-outline-danger btn-sm btn-block"
                    data-confirm-modal
                    data-confirm-tone="danger"
                    data-confirm-title="Rechazar envío"
                    data-confirm-message="¿Confirma el rechazo de este pedido? Se liberará la planificación logística.">
                <i class="fas fa-times mr-1"></i> Rechazar
            </button>
        </form>
    </details>
</div>
@endif
