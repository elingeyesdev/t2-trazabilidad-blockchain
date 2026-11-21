@extends('layouts.app')
@section('content_class', 'ag-operacion ag-pedidos-entregas')
@section('title', 'Seguimiento de entrega | AgroFusion')
@section('page_title', 'Seguimiento de entrega')
@section('content')
@include('logistica.incidentes.enlace', ['tipoAfectado' => $envio['tipo'] === 'agricola' ? 'envio_agricola' : $envio['tipo'], 'idAfectado' => $envio['id']])
<x-operacion.encabezado :titulo="$envio['referencia']" descripcion="Consulte el envío y los comprobantes de recepción disponibles para su cuenta." />
<div class="card mb-3"><div class="card-body">
    <div class="op-acciones mb-3">
        <span class="badge badge-light border">{{ $envio['tipo'] === 'agricola' ? \App\Support\EnvioAsignacionEstadoCatalogo::etiqueta($envio['estado']) : \App\Support\RutaDistribucionCatalogo::etiquetaEstado($envio['estado']) }}</span>
        <span class="text-muted small">{{ $envio['tipo'] === 'agricola' ? 'Agrícola a planta' : ($envio['tipo'] === 'traslado' ? 'Planta a mayorista' : 'Distribución a puntos de venta') }}</span>
    </div>
    @foreach($envio['destinos'] as $destino)
        <p class="mb-2"><strong>Destino:</strong> {{ $destino['nombre'] ?? 'Sin nombre registrado' }} <span class="text-muted">{{ $destino['direccion'] ?? '' }}</span></p>
    @endforeach
</div></div>
<div class="card mb-3">
    <div class="card-header"><h3 class="card-title">Pedidos y cantidades del envío</h3></div>
    <div class="table-responsive"><table class="table op-tabla-movil mb-0">
        <thead><tr><th>Pedido / Producto</th><th>Presentación</th><th>Cantidad enviada</th></tr></thead>
        <tbody>@forelse($envio['lineas'] as $linea)
            <tr><td data-label="Pedido / Producto"><span class="d-block text-muted small">{{ $linea['pedido'] }}</span>{{ $linea['producto'] }}</td>
                <td data-label="Presentación">{{ $linea['presentacion'] ?: 'Sin presentación registrada' }}</td>
                <td data-label="Cantidad enviada"><x-operacion.cantidad :valor="$linea['cantidad_enviada']" :unidad="$linea['unidad']" /></td></tr>
        @empty<tr><td colspan="3" class="op-vacio">No hay líneas disponibles para su cuenta.</td></tr>@endforelse</tbody>
    </table></div>
</div>
<section class="card" aria-labelledby="comprobantes-titulo">
    <div class="card-header"><h3 class="card-title" id="comprobantes-titulo">Comprobantes de recepción</h3></div>
    <div class="card-body">
        @forelse($comprobantes as $comprobante)
            <div class="op-comprobante">
                <div><strong class="d-block">Recepción confirmada</strong><span class="small text-muted">{{ $comprobante['fecha']->timezone('America/La_Paz')->format('d/m/Y H:i') }} · Comprobante #{{ $comprobante['id'] }}</span></div>
                <a class="btn btn-outline-success btn-sm" href="{{ $comprobante['url'] }}">Abrir comprobante</a>
            </div>
        @empty<p class="text-muted mb-0">Sin comprobantes de recepción disponibles para su cuenta. Aparecerán cuando se confirme la entrega correspondiente.</p>@endforelse
    </div>
</section>
@endsection
