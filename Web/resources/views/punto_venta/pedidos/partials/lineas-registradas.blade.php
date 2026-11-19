<div class="table-responsive mb-3">
    <table class="table table-vcenter mb-0">
        <thead><tr><th>Producto solicitado</th><th>Presentación registrada</th><th>Cantidad solicitada</th><th>Origen</th></tr></thead>
        <tbody>
        @foreach($pedido->detalles as $linea)
            <tr>
                <td>{{ $linea->producto_nombre }}<small class="d-block text-muted">Línea #{{ $linea->getKey() }}</small></td>
                <td>{{ $linea->datos_solicitud['presentacion'] ?? 'Sin presentación conservada' }}</td>
                <td><x-operacion.cantidad :valor="$linea->getRawOriginal('cantidad')" :unidad="$linea->datos_solicitud['unidad'] ?? null" />
                    @if(isset($linea->datos_solicitud['cantidad_kg']))<small class="d-block text-muted"><x-operacion.cantidad :valor="$linea->datos_solicitud['cantidad_kg']" unidad="kg" /></small>@endif
                </td>
                <td>Almacén #{{ $linea->almacen_mayorista_origenid ?? $pedido->almacen_mayorista_origenid }}
                    @if($linea->inventario_presentacion_loteid)<small class="d-block text-muted">Partida #{{ $linea->inventario_presentacion_loteid }}</small>@endif
                </td>
            </tr>
        @endforeach
        </tbody>
    </table>
</div>
