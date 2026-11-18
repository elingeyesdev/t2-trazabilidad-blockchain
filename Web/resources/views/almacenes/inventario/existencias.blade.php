@extends('layouts.app')
@section('title', 'Existencias | '.$almacen->nombre)
@section('page_title', 'Existencias por almacén')
@push('styles')<style>.existencias-tabla tbody td { vertical-align: top !important; }</style>@endpush
@section('content')
@php
    $estados = ['bajo' => 'Existencias bajas', 'vencido' => 'Vencido', 'proximo_a_vencer' => 'Próximo a vencer', 'vigente' => 'Vigente', 'sin_fecha_registrada' => 'Sin fecha registrada'];
    $tipos = \App\Models\TipoMovimientoAlmacen::where('activo', true)->orderBy('nombre')->get();
@endphp
<div class="d-flex flex-wrap justify-content-between align-items-center mb-3" style="gap:.75rem">
    <div><div class="text-muted small">{{ $tituloModulo }}</div><h2 class="h4 mb-0">{{ $almacen->nombre }}</h2></div>
    <div class="d-flex flex-wrap" style="gap:.5rem">
        @can('almacen.movimientos.view')<a class="btn btn-outline-secondary" href="{{ route($rutaPrefijo.'.existencias.movimientos', $almacen) }}">Movimientos de este almacén</a>@endcan
        <a class="btn btn-outline-secondary" href="{{ route($rutaPrefijo.'.show', $almacen) }}">Volver al almacén</a>
    </div>
</div>
@if($errors->any())<div class="alert alert-danger"><strong>No se guardaron los cambios.</strong><ul class="mb-0">@foreach($errors->all() as $error)<li>{{ $error }}</li>@endforeach</ul></div>@endif
@if(session('success'))<div class="alert alert-success" role="status">{{ session('success') }}</div>@endif
<div class="card mb-3"><div class="card-body">
    <form method="GET" class="row align-items-end">
        <div class="col-md-5 form-group mb-md-0"><label for="existencia-q">Producto o insumo</label><input id="existencia-q" name="q" class="form-control" value="{{ request('q') }}" maxlength="100"></div>
        <div class="col-md-4 form-group mb-md-0"><label for="existencia-estado">Situación</label><select id="existencia-estado" name="estado" class="form-control"><option value="">Todas</option>@foreach($estados as $valor => $texto)<option value="{{ $valor }}" @selected(request('estado') === $valor)>{{ $texto }}</option>@endforeach</select></div>
        <div class="col-md-3"><button class="btn btn-success">Filtrar</button> <a class="btn btn-outline-secondary" href="{{ route($rutaPrefijo.'.existencias.index', $almacen) }}">Limpiar</a></div>
    </form>
</div></div>
<div class="card"><div class="card-header"><h3 class="card-title mb-0">Saldo y partidas</h3></div>
    <div class="table-responsive"><table class="table existencias-tabla mb-0">
        <thead><tr><th>Producto / unidad</th><th>Físico</th><th>Reservado</th><th>Vencido / bloqueado</th><th>Disponible para uso</th><th>Mínimo y aviso</th><th>Partidas y acciones</th></tr></thead>
        <tbody>@forelse($productos as $producto)
        <tr>
            <td><strong>{{ $producto['nombre'] }}</strong><div class="text-muted small">{{ $producto['unidad'] }}</div></td>
            <td class="text-nowrap">{{ \App\Support\CosechaDecimal::mostrar($producto['cantidad_fisica']) }}</td>
            <td>{{ \App\Support\CosechaDecimal::mostrar($producto['cantidad_reservada']) }}</td>
            <td>{{ \App\Support\CosechaDecimal::mostrar($producto['cantidad_vencida']) }} / {{ \App\Support\CosechaDecimal::mostrar($producto['cantidad_bloqueada']) }}</td>
            <td><strong>{{ \App\Support\CosechaDecimal::mostrar($producto['cantidad_disponible']) }}</strong>@unless($producto['saldo_coherente'])<div class="text-danger small">Revisar desglose de partidas</div>@endunless</td>
            <td>{{ $producto['minimo'] === null ? 'Sin configurar' : \App\Support\CosechaDecimal::mostrar($producto['minimo']) }}
                @if($producto['existencias_bajas'])<div><span class="badge badge-warning">Existencias bajas</span></div>@endif
            </td>
            <td style="min-width:260px;max-width:420px"><details @if($errors->any() && (string) old('existencia_form', old('insumoid')) === (string) $producto['insumoid']) open @endif><summary class="text-success">Ver partidas{{ $puedeConfigurar ? ' y gestionar' : '' }}</summary>
                <div class="pt-3">
                    @foreach($producto['partidas'] as $partida)
                    <div class="border-bottom pb-2 mb-2"><strong>{{ $partida['referencia'] ?: 'Partida #'.($partida['materiaprimaloteid'] ?? $partida['inventario_presentacion_loteid']) }}</strong>
                        <div>{{ \App\Support\CosechaDecimal::mostrar($partida['cantidad_fisica']) }} {{ $producto['unidad'] }} · {{ $partida['fecha_vencimiento'] ?: 'Sin fecha registrada' }}</div>
                        <span class="badge badge-{{ $partida['vencimiento_estado'] === 'vencido' ? 'danger' : ($partida['vencimiento_estado'] === 'proximo_a_vencer' ? 'warning' : 'secondary') }}">{{ $estados[$partida['vencimiento_estado']] }}</span>
                        @unless($partida['utilizable'])<span class="small text-danger">No utilizable</span>@endunless
                    </div>
                    @endforeach
                    <p class="small text-muted">Sin partida histórica: {{ \App\Support\CosechaDecimal::mostrar($producto['cantidad_sin_partida']) }} {{ $producto['unidad'] }}. Sin fecha registrada.</p>
                    @if($puedeConfigurar)
                    <form action="{{ route($rutaPrefijo.'.existencias.minimo', [$almacen, $producto['insumoid']]) }}" method="POST" class="mb-3">@csrf @method('PATCH')
                        <input type="hidden" name="existencia_form" value="{{ $producto['insumoid'] }}">
                        <label for="minimo-{{ $producto['insumoid'] }}">Mínimo de este almacén</label>
                        <input id="minimo-{{ $producto['insumoid'] }}" name="stockminimo" inputmode="decimal" class="form-control form-control-sm" value="{{ old('stockminimo', $producto['minimo']) }}">
                        <small class="text-muted d-block mb-2">Vacío: sin configurar. 0 es un mínimo válido. Se avisa cuando el disponible es igual o menor.</small><button class="btn btn-sm btn-outline-success">Guardar mínimo</button>
                    </form>
                    @foreach(['ingreso' => 'Ingreso o ajuste positivo', 'salida' => 'Salida, merma o ajuste negativo'] as $naturaleza => $etiqueta)
                    @can($naturaleza === 'ingreso' ? 'almacen.ingresos.create' : 'almacen.salidas.create')
                    <details class="border-top pt-2 mt-2"><summary>{{ $etiqueta }}</summary><form method="POST" action="{{ route($rutaPrefijo.'.movimientos.store', ['naturaleza' => $naturaleza]) }}" class="pt-2">@csrf
                        <input type="hidden" name="almacenid" value="{{ $almacen->almacenid }}"><input type="hidden" name="insumoid" value="{{ $producto['insumoid'] }}">
                        <label class="d-block">Tipo<select class="form-control form-control-sm" name="tipo_movimiento_almacenid" required>@foreach($tipos->where('naturaleza', $naturaleza) as $tipo)<option value="{{ $tipo->tipo_movimiento_almacenid }}" @selected((string) old('tipo_movimiento_almacenid') === (string) $tipo->tipo_movimiento_almacenid)>{{ $tipo->nombre }}</option>@endforeach</select></label>
                        <label class="d-block">Cantidad (variación en {{ $producto['unidad'] }})<input name="cantidad" inputmode="decimal" class="form-control form-control-sm" required value="{{ old('cantidad') }}"></label>
                        <label class="d-block">Partida<select name="partida" class="form-control form-control-sm"><option value="">Nueva partida al ingresar / seleccionar al salir</option><option value="0" @selected(old('partida') === '0')>Saldo sin partida histórica</option>@foreach($producto['partidas'] as $partida)<option value="{{ $partida['materiaprimaloteid'] ? 'm:'.$partida['materiaprimaloteid'] : 'p:'.$partida['inventario_presentacion_loteid'] }}" @selected(old('partida') === ($partida['materiaprimaloteid'] ? 'm:'.$partida['materiaprimaloteid'] : 'p:'.$partida['inventario_presentacion_loteid']))>{{ $partida['referencia'] ?: '#'.$partida['materiaprimaloteid'] }} · {{ $estados[$partida['vencimiento_estado']] }}</option>@endforeach</select></label>
                        <label class="d-block">Fecha del movimiento<input type="date" name="fecha" class="form-control form-control-sm" required value="{{ old('fecha', now()->toDateString()) }}"></label>
                        @if($naturaleza === 'ingreso' && $producto['presentaciones'] !== [])<label class="d-block">Presentación de nuevo ingreso<select name="insumo_presentacionid" class="form-control form-control-sm"><option value="">Seleccionar para nueva partida</option>@foreach($producto['presentaciones'] as $presentacion)<option value="{{ $presentacion['insumo_presentacionid'] }}" @selected((string) old('insumo_presentacionid') === (string) $presentacion['insumo_presentacionid'])>{{ $presentacion['nombre'] }}</option>@endforeach</select></label><label class="d-block">Unidades físicas de presentación<input name="cantidad_unidades" inputmode="decimal" class="form-control form-control-sm" value="{{ old('cantidad_unidades') }}"></label>@endif
                        @if($naturaleza === 'ingreso')<label class="d-block">Referencia de nueva partida<input name="lote_proveedor" maxlength="100" class="form-control form-control-sm" value="{{ old('lote_proveedor') }}"></label><label class="d-block">Vencimiento de nueva partida<input type="date" name="fecha_vencimiento" class="form-control form-control-sm" value="{{ old('fecha_vencimiento') }}"></label><small class="text-muted d-block">Un ajuste conserva el vencimiento: deja vacíos los campos de nueva partida.</small>@endif
                        <label class="d-block">Motivo<input name="destino_motivo" maxlength="150" class="form-control form-control-sm" required value="{{ old('destino_motivo') }}"></label>
                        <label class="d-block">Referencia de origen<input name="referencia" maxlength="100" class="form-control form-control-sm" value="{{ old('referencia') }}"></label><button class="btn btn-sm btn-success">Registrar movimiento</button>
                    </form></details>
                    @endcan
                    @endforeach
                    @endif
                </div>
            </details></td>
        </tr>
        @empty<tr><td colspan="7" class="text-center text-muted py-4">No hay existencias para estos filtros.</td></tr>@endforelse</tbody>
    </table></div><div class="card-footer">{{ $productos->links() }}</div>
</div>
<p class="small text-muted mt-3">Próximo a vencer: dentro de {{ config('inventario.dias_aviso_vencimiento') }} días, incluido el límite. Puede consumirse hasta el final del día de vencimiento, hora de Bolivia. Las cantidades mantienen la unidad de cada producto.</p>
@endsection
