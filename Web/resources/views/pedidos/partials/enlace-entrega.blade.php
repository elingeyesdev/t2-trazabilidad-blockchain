@php
    $envioRelacionado = $pedido instanceof \App\Models\Pedido ? $pedido->envioAsignacion : $pedido->rutaDistribucion;
    $urlSeguimiento = app(\App\Services\EntregaWebPresentacionService::class)->seguimientoUrl($envioRelacionado, auth()->user());
@endphp
@if($urlSeguimiento)
<div class="card mb-3"><div class="card-body op-comprobante">
    <div><strong class="d-block">Envío relacionado</strong><span class="small text-muted">Consulte el estado, las cantidades enviadas y su comprobante de recepción.</span></div>
    <a href="{{ $urlSeguimiento }}" class="btn btn-outline-success btn-sm">Ver envío y entrega</a>
</div></div>
@endif
