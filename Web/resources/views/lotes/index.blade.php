@extends('layouts.tabler-lotes')

@section('title', 'Lotes | AgroFusion')

@php
    use App\Support\EstadoLoteCatalogo;
    $filtrosActivos = collect($filtros ?? [])->filter(fn ($v) => $v !== null && $v !== '');
    $filtrosAbiertos = EstadoLoteCatalogo::filtrosPanelAbierto(request(), $filtrosActivos->isNotEmpty());
    $semillaFiltroLabel = ($filtros['insumosemillaid'] ?? '')
        ? (\App\Models\Insumo::find((int) $filtros['insumosemillaid'])?->nombre ?? '') : '';
    $encargadoFiltro = $usuarios->firstWhere('usuarioid', (int) ($filtros['usuarioid'] ?? 0));
    $encargadoFiltroLabel = $encargadoFiltro ? trim($encargadoFiltro->nombre.' '.$encargadoFiltro->apellido) : '';
@endphp

@section('header')
    <div class="row align-items-center g-3">
        <div class="col">
            <div class="page-pretitle">Campo · Lotes y actividades</div>
            <h1 class="page-title">Lotes</h1>
            <p class="text-secondary mb-0 mt-1">Consulta tus lotes, actividades y trazabilidad.</p>
        </div>
        @can('lotes.create')
            <div class="col-12 col-sm-auto"><a class="btn btn-primary" href="{{ route('lotes.create') }}"><i class="ti ti-plus me-2" aria-hidden="true"></i>Nuevo lote</a></div>
        @endcan
    </div>
@endsection

@section('content')
    @foreach(['success' => 'success', 'error' => 'danger', 'warning' => 'warning', 'info' => 'info'] as $key => $tone)
        @if(session($key))
            <div class="alert alert-{{ $tone }}" role="{{ $key === 'error' ? 'alert' : 'status' }}">
                @if($key === 'error' && session('error_modal_titulo'))<strong>{{ session('error_modal_titulo') }}.</strong> @endif
                {{ session($key) }}
            </div>
        @endif
    @endforeach
    @if($errors->any())
        <div class="alert alert-danger" role="alert"><ul class="mb-0">@foreach($errors->all() as $error)<li>{{ $error }}</li>@endforeach</ul></div>
    @endif

    <div class="row row-cards mb-4" aria-label="Resumen de lotes visibles">
        @foreach(['Lotes registrados' => $stats['total'], 'Lotes planificados' => $stats['planificados'], 'Superficie total (ha)' => number_format($stats['hectareas'], 1)] as $label => $value)
            <div class="col-6 col-lg-3"><div class="card card-sm"><div class="card-body"><div class="text-secondary mb-2">{{ $label }}</div><div class="h1 mb-0">{{ $value }}</div></div></div></div>
        @endforeach
        <div class="col-6 col-lg-3"><div class="card card-sm"><div class="card-body"><div class="text-secondary mb-2">En crecimiento</div><a class="h1 mb-0 text-reset" href="{{ route('lotes.index', ['estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('en_crecimiento')]) }}" aria-label="Ver {{ $stats['en_produccion'] }} lotes en crecimiento">{{ $stats['en_produccion'] }}</a></div></div></div>
    </div>
    <div class="text-secondary small mb-4">
        <div><strong>Estados del lote:</strong> al crear queda en Planificado. Pasa a En crecimiento al completar la siembra y a Cosechado al registrar la cosecha. También puedes cambiarlo manualmente al editar el lote.</div>
    </div>

    <section class="card" aria-labelledby="listadoTitulo">
        <div class="card-header d-flex flex-wrap gap-3 justify-content-between">
            <h2 class="card-title" id="listadoTitulo">Listado de lotes <span class="badge bg-secondary-lt ms-2">{{ $lotes->total() }} registros</span></h2>
            <div class="d-flex gap-2 lotes-toolbar">
                <button type="button" class="btn btn-sm" data-bs-toggle="collapse" data-bs-target="#filtrosLotesPanel" aria-controls="filtrosLotesPanel" aria-expanded="{{ $filtrosAbiertos ? 'true' : 'false' }}"><i class="ti ti-filter me-1" aria-hidden="true"></i>Filtros @if($filtrosActivos->isNotEmpty())<span class="badge bg-primary-lt ms-1">{{ $filtrosActivos->count() }}</span>@endif</button>
                <div class="btn-group" role="group" aria-label="Presentación del listado">
                    <button type="button" class="btn btn-sm active" data-lotes-view="table" aria-pressed="true"><i class="ti ti-list me-1" aria-hidden="true"></i>Tabla</button>
                    <button type="button" class="btn btn-sm" data-lotes-view="cards" aria-pressed="false"><i class="ti ti-layout-grid me-1" aria-hidden="true"></i>Tarjetas</button>
                </div>
            </div>
        </div>
        <div id="filtrosLotesPanel" class="collapse {{ $filtrosAbiertos ? 'show' : '' }}">
            <form class="card-body border-bottom" method="GET" action="{{ route('lotes.index') }}">
                <input type="hidden" name="filtros_abiertos" value="1">
                @if(request()->filled('cultivoid') && !request()->filled('insumosemillaid'))<input type="hidden" name="cultivoid" value="{{ request('cultivoid') }}">@endif
                <div class="row g-3">
                    <div class="col-md-6 col-lg-3">
                        <label class="form-label" for="buscarLote">Buscar</label>
                        <input id="buscarLote" type="search" name="q" class="form-control" value="{{ $filtros['q'] ?? '' }}" placeholder="Nombre, calle o código TRAZ">
                    </div>
                    <div class="col-md-6 col-lg-3">
                        <x-tabler.catalogo-filter name="insumosemillaid" label="Semilla / cultivo" :value="$filtros['insumosemillaid'] ?? ''" :selected-label="$semillaFiltroLabel" :endpoint="route('catalogo-selector.insumos')" :params="['tipo_slug' => 'material_siembra']" />
                    </div>
                    <div class="col-md-6 col-lg-3">
                        <label class="form-label" for="estadoLote">Estado</label>
                        <select id="estadoLote" name="estadolotetipoid" class="form-select">
                            <option value="">Todos los estados</option>
                            @foreach($estados as $estado)
                                @php $slug = EstadoLoteCatalogo::slugFromNombre($estado->nombre); @endphp
                                <option value="{{ $estado->estadolotetipoid }}" @selected(($filtros['estadolotetipoid'] ?? '') == $estado->estadolotetipoid) title="{{ $slug ? EstadoLoteCatalogo::descripcion($slug) : '' }}">{{ $slug ? EstadoLoteCatalogo::label($slug) : $estado->nombre }}</option>
                            @endforeach
                        </select>
                    </div>
                    <div class="col-md-6 col-lg-3">
                        <x-tabler.catalogo-filter name="usuarioid" label="Encargado" :value="$filtros['usuarioid'] ?? ''" :selected-label="$encargadoFiltroLabel" :endpoint="route('catalogo-selector.usuarios')" :params="['roles' => 'agricultor,jefe_agricultor']" />
                    </div>
                </div>
                <div class="d-flex flex-wrap gap-2 mt-3 align-items-center">
                    <button type="submit" class="btn btn-primary"><i class="ti ti-search me-2" aria-hidden="true"></i>Aplicar filtros</button>
                    <a class="btn" href="{{ route('lotes.index', ['filtros_abiertos' => 1]) }}">Limpiar filtros</a>
                    @if($filtrosActivos->isNotEmpty())<span class="text-secondary ms-sm-auto" role="status">{{ $lotes->total() }} resultados</span>@endif
                </div>
            </form>
        </div>
        <div id="tableView" class="table-responsive">
            <table class="table table-vcenter table-hover card-table lotes-table">
                <caption class="visually-hidden">Lotes visibles para el usuario autenticado</caption>
                <thead><tr><th scope="col">Lote</th><th scope="col">Encargado</th><th scope="col">Semilla / cultivo</th><th scope="col">Estado</th><th scope="col" class="text-end">Superficie</th><th scope="col">Ubicación</th><th scope="col">Acciones</th></tr></thead>
                <tbody>
                @forelse($lotes as $lote)
                    <tr>
                        <td><a class="fw-semibold" href="{{ route('lotes.show', $lote) }}">{{ $lote->nombre }}</a></td>
                        <td>{{ $lote->usuario->nombre ?? '—' }}</td>
                        <td>{{ $lote->cultivo_etiqueta ?? '—' }}</td>
                        <td><x-tabler.lote-state :nombre="$lote->estadoTipo->nombre ?? 'Sin estado'" /></td>
                        <td class="text-end text-nowrap">@superficie($lote->superficie, 1)</td>
                        <td class="text-secondary" title="{{ $lote->ubicacion_visible }}">{{ Str::limit($lote->ubicacion_visible, 28) }}</td>
                        <td><x-tabler.lote-actions :lote="$lote" /></td>
                    </tr>
                @empty
                    <tr><td colspan="7">@include('lotes.partials.tabler-empty')</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
        <div id="cardView" hidden>
            @forelse($lotes as $lote)
                <article class="lote-card">
                    <div class="d-flex flex-wrap gap-2 justify-content-between align-items-center mb-2">
                        <a class="fw-semibold" href="{{ route('lotes.show', $lote) }}">{{ $lote->nombre }}</a>
                        <x-tabler.lote-state :nombre="$lote->estadoTipo->nombre ?? 'Sin estado'" />
                    </div>
                    <div class="text-secondary mb-3 d-flex flex-wrap gap-2">
                        <span>{{ $lote->usuario->nombre ?? '—' }}</span><span>· {{ $lote->cultivo_etiqueta ?? 'Sin semilla' }}</span><span>· @superficie($lote->superficie, 1)</span>
                        @if($lote->fechasiembra)<span>· {{ \Carbon\Carbon::parse($lote->fechasiembra)->format('d/m/Y') }}</span>@endif
                        <span>· {{ $lote->ubicacion_visible }}</span>
                    </div>
                    <x-tabler.lote-actions :lote="$lote" />
                </article>
            @empty
                @include('lotes.partials.tabler-empty')
            @endforelse
        </div>
        <div class="card-footer d-flex flex-wrap gap-3 align-items-center justify-content-between">
            <span class="text-secondary">{{ $lotes->firstItem() ?? 0 }}–{{ $lotes->lastItem() ?? 0 }} de {{ $lotes->total() }} lotes</span>
            {{ $lotes->onEachSide(1)->links('components.tabler.pagination') }}
        </div>
    </section>
@endsection

@if(session('lote_creado_modal'))
    @push('modals')
        @php $modalLote = session('lote_creado_modal'); @endphp
        <div class="modal fade" id="modalLoteCreado" tabindex="-1" aria-labelledby="modalLoteCreadoTitulo" aria-hidden="true">
            <div class="modal-dialog modal-dialog-centered"><div class="modal-content">
                <div class="modal-header"><h2 class="modal-title" id="modalLoteCreadoTitulo">Lote creado con éxito</h2><button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Cerrar"></button></div>
                <div class="modal-body">Se creó correctamente el lote <strong>«{{ $modalLote['nombre'] ?? '—' }}»</strong>. Puedes registrar actividades o consultar su trazabilidad.</div>
                <div class="modal-footer"><button type="button" class="btn" data-bs-dismiss="modal">Cerrar</button><a class="btn btn-primary" href="{{ $modalLote['trazabilidad_url'] ?? route('lotes.index') }}">Ir ahora</a></div>
            </div></div>
        </div>
    @endpush
@endif
