@php
    $pollingUrl = $pollingUrl ?? route('cierre.firmas-estado');
    $qrUrl = $qrUrl ?? ($resumen['qr_recepcion_url'] ?? null);
    $pollingRuta = $pollingRuta ?? null;
    $pollingAsignacion = $pollingAsignacion ?? null;
@endphp

@if(!empty($resumen['qr_recepciones']))
<div class="card border mb-3"><div class="card-body">
    <h3 class="h6">Recepción por destinatario</h3>
    <p class="small text-muted">Cada destinatario confirma únicamente sus productos con su cuenta y su código.</p>
    <div class="d-flex flex-wrap" style="gap:1.5rem">
    @foreach($resumen['qr_recepciones'] as $qrDestino)
        <div><strong class="d-block mb-2">{{ $qrDestino['destinatario'] }}</strong>
        @if($qrDestino['utilizado'])
            <span class="badge badge-success">Código utilizado</span><a class="d-block small mt-2" href="{{ $qrDestino['comprobante'] }}">Ver comprobante</a>
        @else
            <div class="js-qr-destinatario" data-qr-url="{{ $qrDestino['url'] }}"></div>
            <a class="d-block small mt-2" href="{{ $qrDestino['url'] }}" target="_blank" rel="noopener">Abrir recepción</a>
        @endif</div>
    @endforeach
    </div>
</div></div>
@once
@push('scripts')
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<script>document.querySelectorAll('.js-qr-destinatario').forEach(function(box){ if(typeof QRCode !== 'undefined') new QRCode(box,{text:box.dataset.qrUrl,width:180,height:180,colorDark:'#263442',colorLight:'#ffffff',correctLevel:QRCode.CorrectLevel.L}); });</script>
@endpush
@endonce
@elseif($qrUrl)
<div class="cierre-ag-qr-recepcion" id="cierre-qr-recepcion"
     data-polling-url="{{ $pollingUrl }}"
     @if($pollingRuta) data-polling-ruta="{{ $pollingRuta }}" @endif
     @if($pollingAsignacion) data-polling-asignacion="{{ $pollingAsignacion }}" @endif>
    <div class="cierre-ag-status cierre-ag-status--firma mb-3">
        <span class="cierre-ag-status__icon"><i class="fas fa-qrcode"></i></span>
        <div class="w-100">
            <strong class="d-block">Firma de recepción desde móvil</strong>
            <span class="small text-muted d-block mb-2">
                El receptor debe escanear el código QR con su teléfono y firmar. Esta pantalla se actualizará automáticamente.
            </span>
            <div id="cierre-qr-canvas" class="d-inline-block p-3 bg-white border rounded" style="line-height:0;"></div>
            <p class="small mt-2 mb-1">
                <a href="{{ $qrUrl }}" target="_blank" rel="noopener" class="text-break">{{ $qrUrl }}</a>
            </p>
            <p class="small text-muted mb-0">
                Si el escaneo falla, abra el enlace en el móvil o use «Abrir en el teléfono».
            </p>
            <p class="small text-muted mt-2 mb-0">
                <i class="fas fa-sync-alt fa-spin mr-1" id="cierre-qr-polling-icon" style="display:none;"></i>
                <span id="cierre-qr-polling-text">Esperando firma del receptor…</span>
            </p>
        </div>
    </div>
</div>

@once
@push('scripts')
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<script src="{{ asset('js/cierre-recepcion-qr-polling.js') }}?v=1"></script>
@endpush
@endonce

@push('scripts')
<script>
(function () {
    const box = document.getElementById('cierre-qr-canvas');
    if (!box || typeof QRCode === 'undefined') return;
    box.innerHTML = '';
    new QRCode(box, {
        text: @json($qrUrl),
        width: 240,
        height: 240,
        colorDark: '#1e293b',
        colorLight: '#ffffff',
        correctLevel: QRCode.CorrectLevel.L,
    });
})();
</script>
@endpush
@endif
