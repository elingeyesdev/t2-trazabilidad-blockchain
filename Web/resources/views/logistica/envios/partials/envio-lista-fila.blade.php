@php
    $operacion = $item['asignacion'] ?? $item['ruta'];
    $urlEntrega = app(\App\Services\EntregaWebPresentacionService::class)->seguimientoUrl($operacion, auth()->user());
    $estadoMod = str_replace('pedido-estado-', '', $item['estado_badge']['clase'] ?? 'agricola');
@endphp
<tr>
    <td data-label="Envío"><a class="font-weight-bold" href="{{ $item['ver_url'] }}">{{ $item['codigo'] }}</a><small class="d-block text-muted">{{ $item['tipo_etiqueta'] }}</small><small class="text-muted">{{ $item['fecha']?->format('d/m/Y') }}</small></td>
    <td data-label="Origen / Destino">
        @if($item['trayecto_partes'])
            <span class="d-block">{{ implode(' · ', $item['trayecto_partes']['recogidas'] ?? []) ?: 'Origen sin registrar' }}</span>
            <small class="d-block text-muted">Hacia {{ $item['trayecto_partes']['destino'] ?? $item['destino_label'] }}</small>
        @else{{ $item['destino_label'] ?: 'Destino sin registrar' }}@endif
    </td>
    <td data-label="Carga">
        @if($item['pedido'])
            @foreach($item['pedido']->detalles as $linea)
                <div class="op-linea-pedido"><span class="d-block">{{ $linea->cultivo_personalizado ?: $linea->insumo?->nombre }}</span><small><x-operacion.cantidad :valor="$linea->getRawOriginal('cantidad')" unidad="kg" /></small></div>
            @endforeach
        @elseif($item['ruta']->esTrasladoPlantaMayorista())
            @foreach($item['ruta']->detallesTraslado as $linea)
                <div class="op-linea-pedido"><span class="d-block">{{ $linea->producto_nombre }}</span><small><x-operacion.cantidad :valor="$linea->cantidad_unidades > 0 ? $linea->getRawOriginal('cantidad_unidades') : $linea->getRawOriginal('cantidad')" :unidad="$linea->cantidad_unidades > 0 ? ($linea->presentacion?->etiquetaUnidad() ?? 'unidades') : 'kg'" /></small></div>
            @endforeach
        @else
            @foreach($item['ruta']->pedidos->flatMap->detalles as $linea)
                <div class="op-linea-pedido"><span class="d-block">{{ $linea->producto_nombre }}</span><small><x-operacion.cantidad :valor="$linea->getRawOriginal('cantidad')" :unidad="$linea->datos_solicitud['unidad'] ?? $linea->presentacion?->etiquetaUnidad() ?? $linea->insumo?->unidadMedida?->abreviatura ?? 'unidades'" /></small></div>
            @endforeach
        @endif
    </td>
    <td data-label="Transporte"><span class="d-block">{{ $item['chofer_nombre'] ?: 'Chofer sin asignar' }}</span><small class="d-block text-muted">{{ $item['vehiculo_placa'] ?: 'Vehículo sin asignar' }}</small>
        @if($item['puede_asignar'])
            @can('pedidos.update')<button type="button" class="btn btn-link btn-sm p-0 btn-asignar-transportista" data-pedido-id="{{ $item['pedido']->getKey() }}" data-pedido-label="{{ $item['pedido']->numero_solicitud }}">Asignar chofer</button>@endcan
        @endif
    </td>
    <td data-label="Estado"><span class="op-estado op-estado--{{ $estadoMod }}">{{ $item['estado_badge']['etiqueta'] }}</span></td>
    <td data-label="Acciones"><div class="op-acciones">
        @include('logistica.envios.partials.envio-lista-acciones', ['item' => $item])
        @if($urlEntrega)<a href="{{ $urlEntrega }}" class="btn btn-sm btn-outline-success">Entrega y comprobantes</a>@endif
    </div></td>
</tr>
