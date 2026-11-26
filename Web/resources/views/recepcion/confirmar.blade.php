@extends('layouts.app')
@section('content_class', 'ag-operacion ag-pedidos-entregas')
@section('title', 'Recepción del envío')
@section('page_title', 'Recepción del envío')
@push('styles')
<style>
@media(max-width:575px){
    .recepcion-lineas thead{display:none}
    .recepcion-lineas,.recepcion-lineas tbody,.recepcion-lineas tr,.recepcion-lineas td{display:block;width:100%}
    .recepcion-lineas tr{padding:.5rem 0;border-bottom:1px solid #e2e8f0}
    .recepcion-lineas td{border:0;padding:.4rem 0}
}
</style>
@endpush
@section('content')
<div class="container-fluid py-3" style="max-width:900px">
    <div class="mb-3"><div class="text-muted small">Envíos / Recepción</div><h1 class="h3 mb-1">{{ $envio['referencia'] }}</h1><span class="badge badge-light border">{{ $envio['tipo'] === 'agricola' ? \App\Support\EnvioAsignacionEstadoCatalogo::etiqueta($envio['estado']) : \App\Support\RutaDistribucionCatalogo::etiquetaEstado($envio['estado']) }}</span></div>
    @if($errors->any())<div class="alert alert-warning" role="alert">{{ $errors->first() }}</div>@endif
    @if(session('exito'))<div class="alert alert-success" role="status">{{ session('exito') }}</div>@endif
    @if($desdeDashboard ?? false)<a class="btn btn-outline-secondary btn-sm mb-3" href="{{ route('dashboard', absolute: false) }}">Volver al inicio</a>@endif
    <div class="card">
        <div class="card-header"><h2 class="card-title mb-0">{{ $qr->utilizado_en ? 'Recepción registrada' : 'Confirmar recepción' }}</h2></div>
        <div class="card-body">
            @foreach($envio['destinos'] as $destino)<p class="mb-2"><strong>Destino:</strong> {{ $destino['nombre'] ?? '' }} <span class="text-muted">{{ $destino['direccion'] ?? '' }}</span></p>@endforeach
            @if($qr->utilizado_en)
                @if($envio['tipo'] === 'agricola' && in_array($envio['estado'], ['recibido_planta', 'entregado', 'entregada'], true))
                    <p class="font-weight-bold text-success">Entrega finalizada</p>
                @endif
                <p>Este código ya fue utilizado el {{ $qr->utilizado_en->format('d/m/Y H:i') }}. Las cantidades y la firma quedaron registradas.</p>
                <a class="btn btn-outline-success" href="{{ route('recepcion.comprobante', $qr->getKey()) }}">Ver comprobante</a>
            @elseif(! $puedeConfirmar)
                <div class="alert alert-secondary mb-0">Puede consultar este envío. La confirmación corresponde al destinatario autorizado.</div>
            @else
                <p class="text-muted small">Revise todas las cantidades antes de firmar. Esta confirmación se realiza una sola vez.</p>
                <form method="POST" action="{{ $accionFirma ?? route('recepcion.publica.firmar', $token, absolute: false) }}" id="recepcion-envio-form">
                    @csrf
                    <div class="table-responsive"><table class="table table-vcenter recepcion-lineas"><thead><tr><th>Pedido / Producto</th><th>Enviado</th><th style="min-width:160px">Recibido</th></tr></thead><tbody>
                    @foreach($envio['lineas'] as $i => $linea)
                        <tr><td><span class="text-muted small">{{ $linea['pedido'] }}</span><div>{{ $linea['producto'] }}</div><span class="small text-muted">{{ $linea['presentacion'] }}</span></td>
                            <td><span class="d-inline d-sm-none text-muted">Enviado: </span>{{ \App\Support\CosechaDecimal::mostrar($linea['cantidad_enviada']) }} {{ $linea['unidad'] }}</td><td>
                                <span class="d-block d-sm-none text-muted small mb-1">Cantidad recibida</span>
                                <input type="hidden" name="lineas[{{ $i }}][id]" value="{{ $linea['id'] }}">
                                <label class="sr-only" for="recibido-{{ $i }}">Cantidad recibida de {{ $linea['producto'] }}</label>
                                <input id="recibido-{{ $i }}" class="form-control form-control-sm" name="lineas[{{ $i }}][cantidad_recibida]" type="number" step="{{ $envio['tipo'] === 'traslado' ? '0.0001' : '0.000001' }}" min="{{ $envio['tipo'] === 'traslado' ? '0' : '0.000001' }}" max="{{ $linea['cantidad_enviada'] }}" value="{{ old('lineas.'.$i.'.cantidad_recibida', $linea['cantidad_enviada']) }}" required>
                                <span class="small text-muted">{{ $linea['unidad'] }}</span>
                                @if($envio['tipo'] === 'traslado')<input class="form-control form-control-sm mt-1" name="lineas[{{ $i }}][motivo]" maxlength="255" aria-label="Motivo de diferencia de {{ $linea['producto'] }}" placeholder="Motivo si existe diferencia">@endif
                            </td></tr>
                    @endforeach
                    </tbody></table></div>
                    <p class="small text-muted">{{ $envio['tipo'] === 'distribucion' ? 'Se requiere recibir la cantidad completa de cada línea.' : 'Los faltantes cierran esta recepción; no habilitan otra recepción con el mismo código.' }}</p>
                    <label class="form-label d-block">Firma del destinatario</label>
                    <canvas data-firma-canvas="recepcion-edt52" width="600" height="180" class="border rounded" style="width:100%;max-width:600px;height:180px;touch-action:none;background:#fff" aria-label="Dibuje su firma"></canvas>
                    <input type="hidden" name="imagen_firma" id="recepcion-firma">
                    <p class="small text-muted">Firma manuscrita de {{ auth()->user()->nombre }} {{ auth()->user()->apellido }}.</p>
                    <div class="d-flex flex-wrap" style="gap:.5rem"><button type="button" class="btn btn-outline-secondary btn-limpiar-firma" data-target="recepcion-edt52">Limpiar firma</button><button class="btn btn-success" type="submit">Confirmar recepción</button></div>
                </form>
            @endif
        </div>
    </div>
</div>
@endsection
@push('scripts')
@if(! $qr->utilizado_en && $puedeConfirmar)
<script src="{{ asset('js/firma-canvas.js') }}?v=3"></script>
<script>
document.getElementById('recepcion-envio-form').addEventListener('submit', function (event) {
    const pad = window.AgroFusionFirmaPads?.get('recepcion-edt52');
    const imagen = pad?.toDataUrl();
    if (!imagen) { event.preventDefault(); alert('Dibuje su firma antes de confirmar.'); return; }
    document.getElementById('recepcion-firma').value = imagen;
    this.querySelector('[type=submit]').disabled = true;
});
</script>
@endif
@endpush
