<section class="card mb-3" id="origen-destino-produccion" aria-labelledby="recorrido-titulo">
    <div class="card-header bg-white">
        <h3 class="card-title font-weight-bold" id="recorrido-titulo">Origen y destino de la producción</h3>
    </div>
    <div class="card-body pb-0">
        <p class="text-muted small mb-3">Recorrido actual del lote, separado de los certificados emitidos. Las cantidades corresponden al lote completo; los parámetros de cada etapa se consultan en su historial.</p>
        <h4 class="h6 font-weight-bold">Materias primas de origen</h4>
    </div>
    @if($recorridoProduccion['restricciones']['origenes'])
        <p class="text-muted small px-3" role="status">Hay información de origen restringida por sus permisos.</p>
    @endif
    @if($recorridoProduccion['origenes'])
    <div class="table-responsive">
        <table class="table table-vcenter mb-0">
            <thead><tr><th>Materia prima / partida</th><th>Cantidad utilizada</th><th>Recepción de la partida</th><th>Antecedentes</th></tr></thead>
            <tbody>
            @foreach($recorridoProduccion['origenes'] as $origen)
                <tr>
                    <td>
                        @if($almacenesPlanta->contains('almacenid', $origen['almacen_id']))
                            <a href="{{ route('almacen-planta.inventario.show', [$origen['almacen_id'], $origen['insumo_id']]) }}">{{ $origen['insumo'] }}</a>
                        @else <span>{{ $origen['insumo'] }}</span> @endif
                        <small class="d-block text-muted">Consumo #{{ $origen['consumo_id'] }}</small>
                        <small class="d-block text-muted">
                            @if($origen['materiaprimaloteid']) Partida de materia prima #{{ $origen['materiaprimaloteid'] }}
                            @elseif($origen['inventario_presentacion_loteid']) Partida de inventario #{{ $origen['inventario_presentacion_loteid'] }}
                            @else Partida sin vincular @endif
                        </small>
                        @if($origen['referencia_partida'])<small class="d-block text-muted">Referencia: {{ $origen['referencia_partida'] }}</small>@endif
                    </td>
                    <td>
                        @if($origen['cantidad_consumida'] === null)
                            <span class="text-muted">Cantidad utilizada no registrada</span>
                        @else
                            <x-operacion.cantidad :valor="$origen['cantidad_consumida']" :unidad="$origen['unidad_registrada']" />
                        @endif
                        @if(!$origen['unidad_registrada'] && $origen['unidad_catalogo_actual'])
                            <small class="d-block text-muted">Unidad actual del catálogo: {{ $origen['unidad_catalogo_actual'] }}. Unidad histórica sin registrar.</small>
                        @endif
                        @if($origen['cantidad_unidades_consumidas'] !== null)
                            <small class="d-block"><x-operacion.cantidad :valor="$origen['cantidad_unidades_consumidas']" :unidad="$origen['unidad_presentacion']" /> · {{ $origen['presentacion'] }}</small>
                        @endif
                        @if($origen['movimiento_consumo_id'])<small class="d-block text-muted">Movimiento #{{ $origen['movimiento_consumo_id'] }}</small>@endif
                    </td>
                    <td>
                        @if($origen['cantidad_recibida'] !== null)
                            <x-operacion.cantidad :valor="$origen['cantidad_recibida']" :unidad="$origen['unidad_recepcion']" />
                            <small class="d-block text-muted">Cantidad recibida; puede utilizarse en varios lotes.</small>
                        @else <span class="text-muted">Recepción sin vínculo registrado</span> @endif
                        @if($origen['recepcion'])<small class="d-block text-muted">Recepción del pedido #{{ $origen['recepcion']['pedidoid'] }} · línea #{{ $origen['recepcion']['detallepedidoid'] }}</small>@endif
                    </td>
                    <td>
                        @if($origen['origen_agricola'])
                            <a href="{{ route('lotes.show', $origen['origen_agricola']['loteid']) }}">Lote agrícola #{{ $origen['origen_agricola']['loteid'] }}</a>
                            <small class="d-block text-muted">Cosecha #{{ $origen['origen_agricola']['produccionid'] }}</small>
                        @elseif($origen['origen_industrial_id'])
                            <a href="{{ route('procesamiento.show', $origen['origen_industrial_id']) }}">Lote de producción #{{ $origen['origen_industrial_id'] }}</a>
                        @elseif($origen['antecedente_restringido'])
                            <span class="text-muted">Antecedente restringido</span>
                        @else <span class="text-muted">Sin antecedente vinculado</span> @endif
                    </td>
                </tr>
            @endforeach
            </tbody>
        </table>
    </div>
    @elseif(!$recorridoProduccion['restricciones']['origenes'])
        <p class="text-muted px-3">Sin materias primas vinculadas</p>
    @endif

    <div class="card-body pb-0 border-top"><h4 class="h6 font-weight-bold">Productos obtenidos y almacenes de destino</h4>
        <p class="small text-muted">Ingresos registrados al terminar la producción. El destino original se conserva aunque cambien las existencias.</p>
    </div>
    @if($recorridoProduccion['restricciones']['destinos'])<p class="text-muted small px-3">Hay ingresos y destinos restringidos por sus permisos.</p>@endif
    @if($recorridoProduccion['ingresos_produccion'])
    <div class="table-responsive">
        <table class="table table-vcenter mb-0">
            <thead><tr><th>Producto / presentación</th><th>Cantidad ingresada</th><th>Destino original registrado</th><th>Registro</th></tr></thead>
            <tbody>
            @foreach($recorridoProduccion['ingresos_produccion'] as $ingreso)
                <tr>
                    <td>{{ $ingreso['producto'] ?? 'Producto sin vínculo registrado' }}
                        <small class="d-block text-muted">{{ $ingreso['presentacion'] ?? 'Presentación sin registrar' }}</small>
                        @if($ingreso['insumo_id'])<small class="d-block text-muted">Producto de catálogo #{{ $ingreso['insumo_id'] }} · partida #{{ $ingreso['partida_id'] }}</small>@endif
                    </td>
                    <td>@if($ingreso['cantidad_ingresada'] !== null)
                            <x-operacion.cantidad :valor="$ingreso['cantidad_ingresada']" :unidad="$ingreso['unidad']" />
                            <small class="d-block text-muted"><x-operacion.cantidad :valor="$ingreso['cantidad_kg']" unidad="kg" /></small>
                        @else <span class="text-muted">Cantidad original no conservada</span> @endif
                    </td>
                    <td>{{ $ingreso['almacen'] }}<small class="d-block text-muted">Almacén #{{ $ingreso['almacen_id'] }}</small></td>
                    <td><span class="d-block">Ingreso #{{ $ingreso['almacenaje_id'] }}</span><small class="text-muted">{{ $ingreso['estado'] }}</small></td>
                </tr>
            @endforeach
            </tbody>
        </table>
    </div>
    @elseif(!$recorridoProduccion['restricciones']['destinos'] && !$recorridoProduccion['restricciones']['ubicaciones_actuales'])
        @if($recorridoProduccion['productos_obtenidos'])
            <p class="text-muted px-3">Hay productos vinculados en las partidas actuales. Cantidad original de producción y almacén de destino original no registrados.</p>
        @else
            <p class="text-muted px-3">Sin productos obtenidos registrados. Almacén de destino no registrado.</p>
        @endif
    @endif

    <div class="card-body pb-0 border-top"><h4 class="h6 font-weight-bold">Ubicación y existencias actuales</h4>
        <p class="small text-muted">Partidas vinculadas directamente a este lote. Sus saldos actuales no son la cantidad producida originalmente.</p>
    </div>
    @if($recorridoProduccion['restricciones']['ubicaciones_actuales'])<p class="text-muted small px-3">Hay ubicaciones actuales restringidas por sus permisos.</p>@endif
    @if($recorridoProduccion['ubicaciones_actuales'])
    <div class="table-responsive">
        <table class="table table-vcenter mb-0">
            <thead><tr><th>Partida / producto</th><th>Existencia actual</th><th>Ubicación actual</th></tr></thead>
            <tbody>
            @foreach($recorridoProduccion['ubicaciones_actuales'] as $partida)
                <tr><td>Partida #{{ $partida['partida_id'] }} · {{ $partida['producto'] }}<small class="d-block text-muted">{{ $partida['presentacion'] }}</small></td>
                    <td><x-operacion.cantidad :valor="$partida['cantidad_actual']" :unidad="$partida['unidad']" /><small class="d-block text-muted"><x-operacion.cantidad :valor="$partida['cantidad_actual_kg']" unidad="kg" /></small></td>
                    <td>{{ $partida['almacen'] }}</td>
                </tr>
            @endforeach
            </tbody>
        </table>
    </div>
    @elseif(!$recorridoProduccion['restricciones']['ubicaciones_actuales'])
        <p class="text-muted px-3">Sin partidas de producto vinculadas</p>
    @endif
</section>
