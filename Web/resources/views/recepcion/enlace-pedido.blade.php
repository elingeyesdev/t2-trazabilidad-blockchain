@php
    $operacionRecepcion = $pedido instanceof \App\Models\Pedido ? $pedido->envioAsignacion : $pedido->rutaDistribucion;
    $codigoRecepcionPropio = null;
    if ($operacionRecepcion && auth()->user() && $operacionRecepcion->firmaTransportista()->exists()) {
        $servicioRecepcion = app(\App\Services\EnvioRecepcionQrService::class);
        $destinatarioRecepcion = (new \App\Models\RecepcionQrEnvio)->forceFill(['destinatario_usuarioid' => auth()->id()]);
        if ($servicioRecepcion->puedeConfirmar($destinatarioRecepcion, auth()->user(), $operacionRecepcion)) {
            foreach ($servicioRecepcion->emitir($operacionRecepcion) as $codigoPropio) {
                if ($servicioRecepcion->puedeConfirmar($codigoPropio, auth()->user(), $operacionRecepcion)) {
                    $codigoRecepcionPropio = $codigoPropio;
                    break;
                }
            }
        }
    }
@endphp
@if($codigoRecepcionPropio)
<div class="card mb-3"><div class="card-body d-flex align-items-center justify-content-between flex-wrap" style="gap:.75rem">
    <div><strong class="d-block">Recepción del envío</strong><span class="small text-muted">{{ $codigoRecepcionPropio->utilizado_en ? 'Código utilizado. Cantidades y firma registradas.' : 'Revise las cantidades y confirme con su firma.' }}</span></div>
    <a class="btn btn-outline-success btn-sm" href="{{ $codigoRecepcionPropio->utilizado_en ? route('recepcion.comprobante', $codigoRecepcionPropio->getKey()) : route('recepcion.publica', $codigoRecepcionPropio->token) }}">{{ $codigoRecepcionPropio->utilizado_en ? 'Ver comprobante' : 'Recibir envío' }}</a>
</div></div>
@endif
