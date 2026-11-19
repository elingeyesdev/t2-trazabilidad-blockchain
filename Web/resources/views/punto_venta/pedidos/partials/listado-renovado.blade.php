@extends('layouts.app')
@section('content_class', 'ag-operacion ag-pedidos-entregas')
@section('title', $esBandejaMayorista ? 'Solicitudes de minoristas' : 'Mis pedidos de distribución')
@section('page_title', $esBandejaMayorista ? 'Pedidos de distribución' : 'Mis pedidos')
@section('content')
<x-operacion.encabezado :titulo="$esBandejaMayorista ? 'Solicitudes recibidas' : 'Solicitudes al mayorista'" descripcion="Localice un pedido, revise su estado y consulte el envío y la recepción." />
<div class="op-metricas op-metricas--tres">
    <x-operacion.metrica :valor="$pendientes->count()" etiqueta="En revisión" detalle="Dentro de los resultados actuales" />
    <x-operacion.metrica :valor="$enRutaTiempoReal->count()" etiqueta="En camino" detalle="Dentro de los resultados actuales" />
    <x-operacion.metrica :valor="$pedidos->where('estado', 'recibido')->count()" etiqueta="Recibidos" detalle="Dentro de los resultados actuales" />
</div>
<div class="card">
    <div class="card-header op-listado-cabecera">
        <h3 class="card-title mb-0">{{ $pedidos->count() }} pedido(s)</h3>
        @if($puedeCrear && ! $esBandejaMayorista)<a href="{{ route('punto-venta.pedidos.create', ['ctx' => 'pdv']) }}" class="btn btn-success btn-sm">Solicitar producto</a>@endif
    </div>
    <div class="card-body border-bottom">
        <form method="GET" action="{{ route('punto-venta.pedidos.index') }}" class="op-filtros">
            <input type="hidden" name="ctx" value="{{ $esBandejaMayorista ? 'mayorista' : 'pdv' }}">
            <div class="form-group"><label for="pedidos-buscar">Buscar</label><input id="pedidos-buscar" type="search" name="q" class="form-control" value="{{ request('q') }}" placeholder="Solicitud, producto o destino"></div>
            <div class="form-group"><label for="pedidos-estado">Estado</label><select id="pedidos-estado" name="estado_grupo" class="custom-select"><option value="">Todos</option>@foreach(\App\Support\PedidoDistribucionCatalogo::etiquetasFiltroEstado() as $valor => $etiqueta)<option value="{{ $valor }}" @selected(request('estado_grupo') === $valor)>{{ $etiqueta }}</option>@endforeach</select></div>
            <div class="form-group"><label for="pedidos-destino">Punto de venta</label><select id="pedidos-destino" name="puntoventaid" class="custom-select"><option value="">Todos los destinos</option>@foreach($puntosVenta as $punto)<option value="{{ $punto->getKey() }}" @selected((string)request('puntoventaid') === (string)$punto->getKey())>{{ $punto->nombre }}</option>@endforeach</select></div>
            @if($esBandejaMayorista)
                <div class="form-group"><label for="pedidos-almacen">Almacén de origen</label><select id="pedidos-almacen" name="almacenid" class="custom-select"><option value="">Todos mis almacenes</option>@foreach($almacenesMayorista as $almacen)<option value="{{ $almacen->getKey() }}" @selected((string)request('almacenid') === (string)$almacen->getKey())>{{ $almacen->nombre }}</option>@endforeach</select></div>
            @endif
            <div class="form-group"><label for="pedidos-desde">Desde</label><input id="pedidos-desde" type="date" name="desde" class="form-control" value="{{ request('desde') }}"></div>
            <div class="form-group"><label for="pedidos-hasta">Hasta</label><input id="pedidos-hasta" type="date" name="hasta" class="form-control" value="{{ request('hasta') }}"></div>
            <div class="op-acciones"><button class="btn btn-success" type="submit">Filtrar</button><a class="btn btn-outline-secondary" href="{{ route('punto-venta.pedidos.index', ['ctx' => $esBandejaMayorista ? 'mayorista' : 'pdv']) }}">Limpiar</a></div>
        </form>
    </div>
    <div class="table-responsive"><table class="table table-hover op-tabla-movil mb-0">
        <thead><tr><th>Solicitud</th><th>Destino</th><th>Productos y cantidades</th><th>Entrega prevista</th><th>Estado</th><th>Acciones</th></tr></thead>
        <tbody>@forelse($pedidos as $pedido)
            @php
                $badge = \App\Support\PedidoDistribucionCatalogo::badgeEstado($pedido);
                $acciones = app(\App\Services\PedidoTransicionService::class)->accionesDisponibles($pedido, auth()->user());
                $urlEntrega = app(\App\Services\EntregaWebPresentacionService::class)->seguimientoUrl($pedido->rutaDistribucion, auth()->user());
            @endphp
            <tr>
                <td data-label="Solicitud"><a class="font-weight-bold" href="{{ route('punto-venta.pedidos.show', ['pedido' => $pedido, 'ctx' => $esBandejaMayorista ? 'mayorista' : 'pdv']) }}">{{ $pedido->numero_solicitud }}</a>
                    @if(\App\Support\PedidoDistribucionCatalogo::esPedidoExterno($pedido))<small class="d-block text-muted">Externo · {{ \App\Support\PedidoDistribucionCatalogo::etiquetaCanal($pedido->canal_origen) }}</small>@endif
                </td>
                <td data-label="Destino">{{ $pedido->puntoVenta?->nombre ?? 'Sin destino registrado' }}@if($esBandejaMayorista)<small class="d-block text-muted">{{ $pedido->puntoVenta?->minorista?->nombre }}</small>@endif</td>
                <td data-label="Productos y cantidades">@foreach($pedido->detalles as $linea)<div class="op-linea-pedido"><span class="d-block">{{ $linea->producto_nombre }}</span><small><x-operacion.cantidad :valor="$linea->getRawOriginal('cantidad')" :unidad="$linea->datos_solicitud['unidad'] ?? $linea->presentacion?->etiquetaUnidad() ?? $linea->insumo?->unidadMedida?->abreviatura ?? 'u.'" /></small></div>@endforeach</td>
                <td data-label="Entrega prevista">{{ $pedido->fecha_entrega_deseada?->format('d/m/Y') ?? 'Sin fecha acordada' }}</td>
                <td data-label="Estado"><span class="op-estado op-estado--{{ $badge['clase'] }}">{{ $badge['etiqueta'] }}</span></td>
                <td data-label="Acciones"><div class="op-acciones"><a class="btn btn-sm {{ $acciones !== [] ? 'btn-outline-success' : 'btn-outline-secondary' }}" href="{{ route('punto-venta.pedidos.show', ['pedido' => $pedido, 'ctx' => $esBandejaMayorista ? 'mayorista' : 'pdv']) }}">{{ $acciones !== [] ? 'Revisar pedido' : 'Ver pedido' }}</a>@if($urlEntrega)<a class="btn btn-sm btn-outline-success" href="{{ $urlEntrega }}">Ver entrega</a>@endif</div></td>
            </tr>
        @empty<tr><td colspan="6" class="op-vacio">No hay pedidos con estos filtros. Puede limpiar la búsqueda para volver a verlos.</td></tr>@endforelse</tbody>
    </table></div>
</div>
@endsection
