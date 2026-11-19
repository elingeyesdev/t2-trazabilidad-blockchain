@if($pedidoDecision?->ultimaDecision)
    @php($decisionRegistrada = $pedidoDecision->ultimaDecision)
    <div class="card mb-3">
        <div class="card-body">
            <h3 class="h6 mb-2">Última decisión del pedido: {{ $decisionRegistrada->estado_resultante === 'rechazado' ? 'Rechazado' : 'Aceptado' }}</h3>
            @if($decisionRegistrada->motivo)
                <p class="mb-2" style="white-space: pre-wrap; overflow-wrap: anywhere">{{ $decisionRegistrada->motivo }}</p>
            @endif
            <small class="text-muted">{{ $decisionRegistrada->fecha?->timezone('America/La_Paz')->format('d/m/Y H:i') }} · Responsable #{{ $decisionRegistrada->usuarioid }}</small>
        </div>
    </div>
@endif
