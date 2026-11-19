@extends('layouts.app')
@section('content_class', 'ag-operacion')



@section('title', 'Cosechas | AgroFusion')

@section('page_title', 'Registro de Cosechas')



@section('breadcrumbs')

    <li class="breadcrumb-item"><a href="{{ route('dashboard') }}">Inicio</a></li>

    <li class="breadcrumb-item active">Cosechas completadas</li>

@endsection







@section('content')

<div class="modulo-prod">



    <x-operacion.encabezado titulo="Cosechas registradas" descripcion="Consulta cantidades, presentaciones y equivalencias conservadas. El registro y los siguientes pasos se gestionan desde cada lote." />
    <div class="op-metricas">
        <x-operacion.metrica :valor="$stats['total'] ?? 0" etiqueta="Cosechas registradas" />
        <x-operacion.metrica :valor="\App\Support\CosechaDecimal::mostrar($stats['kg_total'] ?? '0')" unidad="kg" etiqueta="Volumen con equivalencia" />
        <x-operacion.metrica :valor="\App\Support\CosechaDecimal::mostrar($stats['promedio'] ?? '0')" unidad="kg" etiqueta="Promedio con equivalencia" />
        <x-operacion.metrica :valor="$stats['lotes'] ?? 0" etiqueta="Lotes cosechados" />
    </div>

    <div class="card card-outline card-success card-modulo-main elevation-1">

        <div class="card-header d-flex flex-wrap align-items-center justify-content-between py-2">

            <h3 class="card-title mb-0">

                <i class="fas fa-list-alt text-success mr-2"></i>

                Listado

                <span class="badge badge-light border ml-2">{{ $producciones->total() }} cosechas</span>

            </h3>

            <button type="button" class="btn btn-sm btn-outline-secondary" data-toggle="collapse" data-target="#filtrosProduccionPanel">

                <i class="fas fa-filter mr-1"></i> Filtros

            </button>

        </div>



        <div id="filtrosProduccionPanel" class="filtros-panel collapse {{ request()->hasAny(['buscar','loteid','fecha_desde','fecha_hasta']) ? 'show' : '' }}">

            <form method="GET" action="{{ route('producciones.index') }}">

                <div class="row align-items-end">

                    <div class="col-lg-4 col-md-6 mb-2">

                        <label class="small text-muted mb-1">Buscar</label>

                        <input type="text" name="buscar" class="form-control form-control-sm" value="{{ request('buscar') }}" placeholder="Lote, semilla u observación…">

                    </div>

                    <div class="col-lg-4 col-md-6 mb-2">

                        <label class="small text-muted mb-1">Lote cosechado</label>

                        @include('partials.selector-catalogo', [
                            'id' => 'cos_filtro_lote',
                            'name' => 'loteid',
                            'value' => request('loteid'),
                            'labelSelected' => $loteFiltroSeleccionado?->nombre ?? '',
                            'endpoint' => route('catalogo-selector.lotes'),
                            'params' => ['loteids' => ($loteIdsCosechadosFilter ?? collect())->implode(',')],
                            'title' => 'Seleccionar lote cosechado',
                            'searchPlaceholder' => 'Nombre, código o ubicación…',
                            'searchLabel' => 'Buscar lote cosechado',
                            'modalIcon' => 'fa-map-marked-alt',
                            'rowIcon' => 'fa-seedling',
                            'colNombre' => 'Lote',
                            'colDetalle' => 'Cultivo / código',
                            'allowEmpty' => true,
                            'emptyLabel' => 'Todos los lotes',
                            'placeholderEmpty' => 'Todos los lotes cosechados',
                            'size' => 'sm',
                            'inputGroup' => true,
                            'showLabel' => false,
                            'variant' => 'filtros',
                        ])

                    </div>

                    <div class="col-lg-2 col-md-4 mb-2">

                        <label class="small text-muted mb-1">Desde</label>

                        <input type="date" name="fecha_desde" class="form-control form-control-sm" value="{{ request('fecha_desde') }}">

                    </div>

                    <div class="col-lg-2 col-md-4 mb-2">

                        <label class="small text-muted mb-1">Hasta</label>

                        <input type="date" name="fecha_hasta" class="form-control form-control-sm" value="{{ request('fecha_hasta') }}">

                    </div>

                    <div class="col-lg-4 col-md-4 mb-2">

                        <x-filtros-form-actions :limpiar-url="route('producciones.index', ['filtros_abiertos' => 1])" />

                    </div>

                </div>

            </form>

        </div>



        <div class="card-body p-0">

            <div class="table-responsive">

                <table class="table table-hover mb-0 cosecha-tabla">

                    <thead>

                        <tr>

                            <th>Lote</th>

                            <th>Semilla / cultivo</th>

                            <th class="text-right">Cantidad cosechada</th>

                            <th>Fecha</th>

                            <th>Superficie</th>

                            <th class="text-center" style="min-width:200px">Acciones</th>

                        </tr>

                    </thead>

                    <tbody>

                        @forelse($producciones as $p)

                            @php
                                $lote = $p->lote;
                                $almacenActivo = $p->almacenamientos->whereNull('fechasalida')->sortByDesc('fechaentrada')->first();
                            @endphp

                            <tr>

                                <td>

                                    <div class="cosecha-lote-nombre">{{ $lote->nombre ?? '—' }}</div>

                                    @if($lote?->usuario)

                                        <div class="cosecha-meta"><i class="fas fa-user mr-1"></i>{{ trim($lote->usuario->nombre.' '.($lote->usuario->apellido ?? '')) }}</div>

                                    @endif

                                </td>

                                <td>
                                    @if($lote?->cultivo_etiqueta)
                                        <span class="cos-chip cos-chip--emerald"><i class="fas fa-seedling"></i>{{ $lote->cultivo_etiqueta }}</span>
                                    @else
                                        <span class="text-muted">—</span>
                                    @endif
                                </td>
                                <td class="text-right">
                                    @php $presentacion = app(\App\Services\CosechaPresentacionService::class)->paraProduccion($p); @endphp
                                    <span class="cosecha-cantidad">{{ \App\Support\CosechaDecimal::mostrar($p->cantidad) }}</span>
                                    <span class="text-muted">{{ $presentacion['unidad_abreviatura'] ?? $p->unidadMedida?->abreviatura ?? $p->unidadMedida?->nombre ?? 'Unidad sin registrar' }}</span>
                                    <div class="cosecha-meta">{{ $presentacion['calibre_nombre'] ?? 'Presentación histórica sin factor' }}</div>
                                    <div class="cosecha-meta">{{ \App\Support\CosechaDecimal::mostrar($p->cantidad_base) }}{{ $p->cantidad_base !== null ? ' kg equivalentes' : ' · equivalencia no registrada' }}</div>
                                    @if($almacenActivo?->almacen)
                                        <div class="mt-1">
                                            <span class="cos-chip cos-chip--sky"><i class="fas fa-warehouse"></i>{{ $almacenActivo->almacen->nombre }}</span>
                                        </div>
                                    @endif
                                </td>
                                <td>
                                    {{ $p->fechacosecha ? \Carbon\Carbon::parse($p->fechacosecha)->format('d/m/Y') : '—' }}
                                </td>
                                <td class="text-muted small">
                                    {{ $lote?->superficie_etiqueta ?? '—' }}
                                    @if($lote?->codigo_trazabilidad)
                                        <div class="cosecha-meta mt-1">Código de trazabilidad: <span style="font-family:ui-monospace,monospace;">{{ $lote->codigo_trazabilidad }}</span></div>
                                    @endif
                                </td>

                                <td class="text-center">

                                    <div class="d-flex flex-wrap justify-content-center" style="gap:6px;">

                                        <a href="{{ route('producciones.show', $p) }}" class="btn btn-sm btn-outline-info" title="Ver detalle de cosecha">

                                            <i class="fas fa-eye mr-1"></i> Detalle

                                        </a>

                                        @if($lote)

                                            <a href="{{ route('lotes.trazabilidad', $lote) }}" class="btn btn-sm btn-ir-lote" title="Ir al lote">

                                                <i class="fas fa-map-marked-alt mr-1"></i> Ir al lote

                                            </a>

                                        @endif

                                    </div>

                                </td>

                            </tr>

                        @empty

                            <tr>

                                <td colspan="6" class="text-center py-5 text-muted">

                                    <i class="fas fa-tractor fa-3x mb-3 d-block opacity-50"></i>

                                    <p class="mb-1 font-weight-bold">No hay cosechas completadas</p>

                                    <p class="small mb-0">Cuando un lote pase a estado <em>Cosechado</em>, aparecerá aquí automáticamente.</p>

                                </td>

                            </tr>

                        @endforelse

                    </tbody>

                </table>

            </div>

        </div>



        @if($producciones->hasPages())

        <div class="card-footer d-flex justify-content-center bg-white">

            {{ $producciones->links() }}

        </div>

        @endif

    </div>

</div>

@endsection

