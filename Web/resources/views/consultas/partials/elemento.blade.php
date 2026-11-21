@php
    $etiquetas = [
        'loteid' => 'Lote agrícola', 'produccionid' => 'Cosecha', 'loteproduccionpedidoid' => 'Lote de planta',
        'consumo_id' => 'Registro de consumo', 'insumo_id' => 'Producto de catálogo', 'insumoid' => 'Producto de catálogo',
        'insumo' => 'Materia prima', 'almacen_id' => 'Almacén', 'almacen' => 'Almacén',
        'referencia_partida' => 'Referencia de partida', 'materiaprimaloteid' => 'Partida de materia prima',
        'inventario_presentacion_loteid' => 'Partida de inventario', 'partida_id' => 'Partida de inventario',
        'movimiento_consumo_id' => 'Movimiento de consumo', 'pedidoid' => 'Pedido agrícola',
        'pedidodistribucionid' => 'Pedido de distribución', 'rutadistribucionid' => 'Envío de distribución',
        'numero_solicitud' => 'Número de pedido', 'codigo' => 'Código del lote', 'producto' => 'Producto obtenido',
        'descripcion' => 'Actividad', 'estado' => 'Estado registrado', 'destino' => 'Destino',
        'destino_tipo' => 'Situación del destino', 'confirmacion' => 'Situación del destino',
        'responsable_id' => 'Responsable', 'proceso' => 'Proceso', 'maquina' => 'Máquina',
        'inicio' => 'Inicio registrado', 'fin' => 'Cierre registrado', 'fecha_recepcion' => 'Recepción registrada',
        'fecha_planificada' => 'Fecha programada', 'fecha_salida' => 'Salida registrada',
        'presentacion' => 'Presentación', 'observaciones' => 'Observaciones',
        'recepcion_id' => 'Comprobante de recepción', 'envio_id' => 'Envío',
        'pedido_id' => 'Pedido', 'almacen_origenid' => 'Almacén de origen', 'almacen_destinoid' => 'Almacén de destino',
    ];
    $cantidades = [
        'cantidad' => ['Cantidad registrada', $datos['unidad'] ?? null],
        'cantidad_consumida' => ['Cantidad consumida', $datos['unidad_registrada'] ?? null],
        'cantidad_recibida' => ['Cantidad recibida', $datos['unidad_recepcion'] ?? $datos['presentacion'] ?? null],
        'cantidad_ingresada' => ['Cantidad ingresada', $datos['unidad'] ?? null],
        'cantidad_actual' => ['Saldo actual', $datos['unidad'] ?? (isset($datos['unidadmedidaid']) ? 'Unidad #'.$datos['unidadmedidaid'] : null)],
        'cantidad_kg' => ['Peso registrado', 'kg'], 'cantidad_actual_kg' => ['Peso actual', 'kg'],
        'cantidad_unidades' => ['Envases registrados', $datos['presentacion'] ?? 'unidades'],
        'cantidad_unidades_consumidas' => ['Envases consumidos', $datos['unidad_presentacion'] ?? $datos['presentacion'] ?? 'unidades'],
    ];
@endphp
@if(!empty($datos['comprobante_url']))<p class="small"><a href="{{ $datos['comprobante_url'] }}">Abrir comprobante de recepción</a></p>@endif
<dl class="row mb-0 small">
    @foreach($cantidades as $clave => [$etiqueta, $unidad])
        @if(array_key_exists($clave, $datos))<dt class="col-sm-4 text-muted">{{ $etiqueta }}</dt><dd class="col-sm-8"><x-operacion.cantidad :valor="$datos[$clave]" :unidad="$unidad ?? 'Unidad histórica no registrada'" /></dd>@endif
    @endforeach
    @foreach($etiquetas as $clave => $etiqueta)
        @if(array_key_exists($clave, $datos) && !is_array($datos[$clave]))<dt class="col-sm-4 text-muted">{{ $etiqueta }}</dt><dd class="col-sm-8 text-break">{{ $datos[$clave] ?? 'Sin dato registrado' }}</dd>@endif
    @endforeach
</dl>
@if(!empty($datos['origen_agricola']))
    <p class="small mb-1">Origen: lote agrícola #{{ $datos['origen_agricola']['loteid'] }} · cosecha #{{ $datos['origen_agricola']['produccionid'] }}</p>
@endif
@if(!empty($datos['recepcion']))
    <p class="small mb-1">Recepción del pedido #{{ $datos['recepcion']['pedidoid'] }} · línea #{{ $datos['recepcion']['detallepedidoid'] }} · {{ $datos['recepcion']['fecha'] ?? 'Fecha no registrada' }}</p>
@endif
@if(!empty($datos['parametros']))
    <details><summary class="small">Parámetros registrados de la etapa</summary>
        @foreach($datos['parametros'] as $parametro)<p class="small mb-1">{{ $parametro['nombre'] ?? 'Parámetro registrado' }}: {{ $parametro['valor'] ?? 'Sin valor registrado' }} {{ $parametro['unidad'] ?? '' }}</p>@endforeach
    </details>
@endif
@foreach(['consumos_vinculados' => 'Consumos de esta cosecha', 'ingresos_produccion' => 'Ingresos de producción'] as $clave => $titulo)
    @if(!empty($datos[$clave]))<details><summary class="small">{{ $titulo }}</summary>@foreach($datos[$clave] as $fila)<div class="border-top pt-2 mt-2">@include('consultas.partials.elemento', ['datos' => $fila])</div>@endforeach</details>@endif
@endforeach
