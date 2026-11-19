@extends('layouts.app')
@section('content_class', 'ag-operacion ag-pedidos-entregas')

@php
    $tituloPagina = ($esTransportista ?? false) ? 'Mis envíos' : 'Envíos';
@endphp
@section('title', $tituloPagina.' | AgroFusion')
@section('page_title', $tituloPagina)

@push('styles')
@include('partials.logistica-modulo-styles')
@include('logistica.partials.ayuda-logistica-styles')
@include('logistica.envios.partials.envio-lista-estilos')
@endpush

@section('content')
@include('logistica.partials.envios-seccion-nav')
<div class="envios-wrap page-envios-lista">
    <x-operacion.encabezado titulo="Pedidos, envíos y entregas" descripcion="Consulte el trayecto, el estado del transporte y los comprobantes de recepción." />
    @if($resumenEnvios ?? null)
    <div class="op-metricas">
        @foreach(['total' => 'Envíos registrados', 'asignados' => 'Pendientes de salida', 'en_camino' => 'En camino', 'recibidos' => 'Entregas confirmadas'] as $key => $label)
            <x-operacion.metrica :valor="$resumenEnvios[$key] ?? 0" :etiqueta="$label" />
        @endforeach
    </div>
    @endif

    <div class="card envios-filtros-card mb-3">
        <div class="card-body py-3">
            <form method="GET" action="{{ $urlListado }}" class="form-row align-items-end op-envios-filtros">
                <div class="col-md-3 mb-2 mb-md-0">
                    <label for="envios-buscar" class="small text-muted mb-1">Buscar</label>
                    <input id="envios-buscar" type="search" name="q" class="form-control form-control-sm"
                           value="{{ request('q') }}" placeholder="Código, cultivo, planta, chofer…">
                </div>
                @unless($esTransportista ?? false)
                @if(($transportistas ?? collect())->isNotEmpty())
                <div class="col-md-2 mb-2 mb-md-0">
                    <label class="small text-muted mb-1">Chofer</label>
                    @include('partials.selector-catalogo', [
                        'id' => 'envios_filtro_transportista',
                        'name' => 'transportista',
                        'value' => request('transportista'),
                        'labelSelected' => $transportistaFiltroNombre ?? '',
                        'endpoint' => route('catalogo-selector.usuarios'),
                        'params' => ['roles' => 'transportista'],
                        'title' => 'Filtrar por chofer',
                        'searchPlaceholder' => 'Nombre, usuario o correo…',
                        'searchLabel' => 'Buscar chofer',
                        'allowEmpty' => true,
                        'emptyLabel' => 'Todos los choferes',
                        'placeholderEmpty' => 'Todos',
                        'inputGroup' => true,
                        'showLabel' => false,
                        'modalIcon' => 'fa-user-tie',
                        'rowIcon' => 'fa-id-badge',
                        'colNombre' => 'Transportista',
                        'colDetalle' => 'Usuario / contacto',
                        'variant' => 'filtros',
                    ])
                </div>
                @endif
                <div class="col-md-2 mb-2 mb-md-0">
                    <label for="envios-vehiculo" class="small text-muted mb-1">Vehículo</label>
                    <input type="text" id="envios-vehiculo" name="vehiculo" class="form-control form-control-sm"
                           value="{{ request('vehiculo') }}" placeholder="Placa">
                </div>
                @endunless
                <div class="col-md-2 mb-2 mb-md-0">
                    <label for="envios-estado" class="small text-muted mb-1">Estado del pedido (agrícola)</label>
                    <select id="envios-estado" name="estado" class="custom-select custom-select-sm">
                        <option value="">Todos</option>
                        @foreach($estadosPedido ?? [] as $estVal => $estLabel)
                            <option value="{{ $estVal }}" @selected(request('estado') === $estVal)>{{ $estLabel }}</option>
                        @endforeach
                    </select>
                </div>
                <div class="col-md-2 mb-2 mb-md-0">
                    <label for="envios-estado_logistica" class="small text-muted mb-1">Estado del transporte</label>
                    <select id="envios-estado_logistica" name="estado_logistica" class="custom-select custom-select-sm">
                        <option value="">Todas</option>
                        @foreach($estadosLogistica ?? [] as $estVal => $estLabel)
                            <option value="{{ $estVal }}" @selected(request('estado_logistica') === $estVal)>{{ $estLabel }}</option>
                        @endforeach
                    </select>
                </div>
                <div class="col-md-2 mb-2 mb-md-0">
                    <label for="envios-desde" class="small text-muted mb-1">Desde</label>
                    <input type="date" id="envios-desde" name="desde" class="form-control form-control-sm" value="{{ request('desde') }}">
                </div>
                <div class="col-md-2 mb-2 mb-md-0">
                    <label for="envios-hasta" class="small text-muted mb-1">Hasta</label>
                    <input type="date" id="envios-hasta" name="hasta" class="form-control form-control-sm" value="{{ request('hasta') }}">
                </div>
                <div class="col-auto mb-2 mb-md-0">
                    <label class="small text-muted mb-1 d-block">&nbsp;</label>
                    <button type="submit" class="btn btn-success btn-sm px-3">
                        <i class="fas fa-filter mr-1"></i> Filtrar
                    </button>
                </div>
            </form>
            @if(request()->except('page'))
                <p class="small text-muted mb-0 mt-2">Filtros activos. <a href="{{ $urlListado }}">Limpiar</a></p>
            @endif
        </div>
    </div>

    <div class="card envios-lista-card mb-3">
        <div class="envios-lista-card__toolbar">
            <div class="d-flex flex-wrap justify-content-between align-items-center">
                <h3 class="card-title mb-2 mb-md-0 font-weight-bold">
                    <i class="fas fa-truck text-success mr-2"></i>{{ $tituloPagina }}
                    <small class="text-muted font-weight-normal">({{ $items->total() }})</small>
                </h3>
                @can('pedidos.create')
                @if(\App\Support\EnvioTrayectoCatalogo::puedeCrearAlguno(auth()->user()))
                <a href="{{ \App\Support\EnvioTrayectoCatalogo::urlCrearEnvio(auth()->user()) }}" class="btn btn-success btn-sm">
                    <i class="fas fa-plus mr-1"></i> Nuevo envío
                </a>
                @endif
                @endcan
            </div>
        </div>
        <div class="table-responsive">
            <table class="table table-hover op-tabla-movil mb-0">
                <thead><tr><th>Envío</th><th>Origen / Destino</th><th>Carga</th><th>Transporte</th><th>Estado</th><th>Acciones</th></tr></thead>
                <tbody>@forelse($items as $item)
                    @include('logistica.envios.partials.envio-lista-fila', ['item' => $item])
                @empty<tr><td colspan="6" class="op-vacio">No hay envíos con estos filtros. Limpie la búsqueda para volver a verlos.</td></tr>@endforelse</tbody>
            </table>
        </div>
        @if($items->hasPages())
        <div class="card-footer bg-white">{{ $items->links() }}</div>
        @endif
    </div>
</div>

@include('partials.modal-confirmar-accion')

@can('pedidos.update')
<form id="formAsignarTransportista" method="POST" class="d-none">
    @csrf
    <input type="hidden" name="transportista_usuarioid" id="inputTransportistaAsignar">
    <input type="hidden" name="vehiculoid" id="inputVehiculoAsignar">
    <input type="hidden" name="costo_bs" id="inputCostoAsignar">
</form>
@once
    @push('styles')
    <style>
        #modalSelectorCatalogo .selector-catalogo-row { cursor: pointer; }
        #modalSelectorCatalogo .selector-catalogo-row:hover { background: #f4f9f4; }
    </style>
    @endpush
    @push('scripts')
    <script src="{{ asset('js/selector-catalogo.js') }}"></script>
    @endpush
@endonce
@push('scripts')
<script>
document.addEventListener('DOMContentLoaded', function () {
    if (!window.CatalogoSelector) return;
    let pedidoIdAsignar = null;
    const form = document.getElementById('formAsignarTransportista');
    const inputTransportista = document.getElementById('inputTransportistaAsignar');
    const inputVehiculo = document.getElementById('inputVehiculoAsignar');
    const urlAsignar = @json(route('pedidos.asignar-transportista', ['pedido' => '__PEDIDO__']));

    const inputCosto = document.getElementById('inputCostoAsignar');

    function solicitarCostoYEnviar() {
        if (!form || !pedidoIdAsignar) return;
        const pedirCosto = (valor) => {
            const costo = parseFloat(String(valor).replace(',', '.'));
            if (!Number.isFinite(costo) || costo <= 0) {
                if (window.Swal) {
                    Swal.fire('Costo inválido', 'Ingrese un monto mayor a 0 en bolivianos.', 'warning');
                } else {
                    alert('Ingrese un costo válido en bolivianos.');
                }
                return;
            }
            inputCosto.value = costo.toFixed(2);
            form.action = urlAsignar.replace('__PEDIDO__', pedidoIdAsignar);
            form.submit();
        };

        if (window.Swal) {
            Swal.fire({
                title: 'Costo del servicio (Bs)',
                input: 'number',
                inputAttributes: { min: '0.01', step: '0.01' },
                inputPlaceholder: 'Ej. 150.00',
                showCancelButton: true,
                confirmButtonText: 'Asignar',
                cancelButtonText: 'Cancelar',
            }).then((result) => {
                if (result.isConfirmed) pedirCosto(result.value);
            });
        } else {
            const valor = prompt('Costo del servicio en bolivianos (Bs):');
            if (valor !== null) pedirCosto(valor);
        }
    }

    document.querySelectorAll('.btn-asignar-transportista').forEach(btn => {
        btn.addEventListener('click', () => {
            pedidoIdAsignar = btn.dataset.pedidoId;
            CatalogoSelector.abrir({
                titulo: 'Asignar transportista',
                subtitulo: 'Pedido ' + (btn.dataset.pedidoLabel || ''),
                tipo: 'transportistas',
                onSeleccionar(item) {
                    if (!form || !pedidoIdAsignar) return;
                    inputTransportista.value = item.id;
                    inputVehiculo.value = item.meta?.vehiculoid || '';
                    solicitarCostoYEnviar();
                },
            });
        });
    });
});
</script>
@endpush
@endcan
@endsection
