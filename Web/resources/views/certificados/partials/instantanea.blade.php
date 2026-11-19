@php($e = $datos['emision'])
@php($r = $datos['recorrido'])
<div class="mb-4">
    <div class="text-muted small">Emisión conservada · Formato {{ $datos['formato_version'] }}</div>
    <h2 class="h4 mt-2" style="overflow-wrap:anywhere">{{ $e['codigo'] }}</h2>
    <p>{{ $e['resultado'] }} · {{ \Illuminate\Support\Carbon::parse($e['fecha'])->format('d/m/Y H:i:s') }}</p>
    <p><strong>Emitido por:</strong> {{ $e['emisor'] }} <span class="text-muted">(#{{ $e['emisor_id'] }})</span></p>
</div>
<h3 class="h5">Producto y origen</h3>
<dl>
    <dt>Nombre</dt><dd>{{ $r['producto']['nombre'] ?? 'Sin nombre registrado' }}</dd>
    <dt>Producto</dt><dd>{{ $r['producto']['producto'] ?? $r['producto']['cultivo'] ?? 'Sin dato registrado' }}</dd>
    @if($r['producto']['codigo_lote'] ?? $r['producto']['codigo_trazabilidad'] ?? null)
        <dt>Código del lote</dt><dd>{{ $r['producto']['codigo_lote'] ?? $r['producto']['codigo_trazabilidad'] }}</dd>
    @endif
    @if($r['producto']['superficie'] ?? null)<dt>Superficie</dt><dd>{{ $r['producto']['superficie'] }} {{ $r['producto']['unidad_superficie'] }}</dd>@endif
    @if($r['producto']['ubicacion'] ?? null)<dt>Ubicación</dt><dd>{{ $r['producto']['ubicacion'] }}</dd>@endif
    @if($r['producto']['plantilla'] ?? null)<dt>Ruta de transformación</dt><dd>{{ $r['producto']['plantilla'] }}</dd>@endif
    @if(isset($r['producto']['cantidad_objetivo']))<dt>Cantidad objetivo</dt><dd>{{ $r['producto']['cantidad_objetivo'] }} {{ $r['producto']['unidad'] }}</dd>@endif
    @if(isset($r['producto']['cantidad_producida']))<dt>Cantidad producida</dt><dd>{{ $r['producto']['cantidad_producida'] }} {{ $r['producto']['unidad'] }}</dd>@endif
</dl>
@if($e['observaciones'])<h3 class="h5">Observaciones</h3><p style="white-space:pre-wrap">{{ $e['observaciones'] }}</p>@endif
@if($e['recomendaciones'])<h3 class="h5">Recomendaciones</h3><p style="white-space:pre-wrap">{{ $e['recomendaciones'] }}</p>@endif
@if($r['cosechas'])
<h3 class="h5 mt-4">Cosechas registradas</h3>
<div class="table-responsive"><table class="table table-sm"><thead><tr><th>Cosecha</th><th>Fecha</th><th>Cantidad registrada</th></tr></thead><tbody>
@foreach($r['cosechas'] as $c)<tr><td>#{{ $c['produccionid'] }}</td><td>{{ $c['fecha'] }}</td><td>{{ $c['cantidad'] }} {{ $c['unidad'] }}</td></tr>@endforeach
</tbody></table></div>
@endif
@if($r['materias_primas'])
<h3 class="h5 mt-4">Materias primas y recepciones vinculadas</h3>
<div class="table-responsive"><table class="table table-sm"><thead><tr><th>Materia prima</th><th>Cantidad usada</th><th>Origen registrado</th></tr></thead><tbody>
@foreach($r['materias_primas'] as $m)
<tr><td>{{ $m['nombre'] ?? 'Sin nombre registrado' }}</td><td>{{ $m['cantidad_usada'] }} {{ $m['unidad'] }}</td>
<td>@if($m['recepcion'])Pedido #{{ $m['recepcion']['pedidoid'] }} · línea #{{ $m['recepcion']['detallepedidoid'] }}
    @if($m['recepcion']['linea_recibida']['origen']['loteid'] ?? null)<br>Lote agrícola #{{ $m['recepcion']['linea_recibida']['origen']['loteid'] }}@endif
    @elseif($m['lote_produccion_origen_id'])Lote de producción #{{ $m['lote_produccion_origen_id'] }}
    @else Sin recepción vinculada @endif</td></tr>
@endforeach
</tbody></table></div>
@endif
<h3 class="h5 mt-4">Etapas registradas al emitir</h3>
@forelse($r['etapas'] as $etapa)
<div class="border rounded p-3 mb-2">
    <strong>{{ $etapa['proceso'] ?? 'Etapa sin nombre registrado' }}</strong>
    @if($etapa['maquina'] ?? null)<span class="text-muted"> · {{ $etapa['maquina'] }}</span>@endif
    <div class="small text-muted">{{ $etapa['fin'] ?? 'Sin cierre registrado' }} · {{ $etapa['responsable'] ?? 'Responsable no registrado' }}</div>
    @if($etapa['resultado'] ?? null)<p class="mb-1">{{ $etapa['resultado'] }}</p>@endif
    @foreach($etapa['parametros'] ?? [] as $p)<div>{{ $p['nombre'] ?? 'Parámetro' }}: {{ $p['valor_decimal'] ?? $p['valor'] ?? 'Sin valor' }} {{ $p['unidad'] ?? '' }}</div>@endforeach
</div>
@empty<p class="text-muted">Sin etapas registradas disponibles.</p>@endforelse
