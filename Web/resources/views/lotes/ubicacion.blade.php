@extends('layouts.tabler-lotes')
@section('title', 'Ubicación del lote | AgroFusion')
@section('header')
    @include('lotes.tabler.header', ['sectionTitle' => 'Ubicación del lote'])
@endsection
@section('content')
    @include('lotes.tabler.navigation')
    <div class="row g-3">
        <div class="col-lg-8">
            <section class="card">
                <div class="card-header"><h2 class="card-title">Mapa del lote</h2></div>
                @if($lote->latitud !== null && $lote->longitud !== null)
                    <div id="map" class="lote-location-map" aria-label="Mapa de ubicación del lote" data-lote-map data-lat="{{ $lote->latitud }}" data-lng="{{ $lote->longitud }}" data-area="{{ $lote->superficie ?? 0 }}" data-name="{{ $lote->nombre }}"></div>
                    <div class="card-footer text-secondary small">El círculo representa una superficie aproximada; no delimita los linderos del terreno.</div>
                @else
                    <div class="empty"><div class="empty-icon"><i class="ti ti-map-pin-off" aria-hidden="true"></i></div><p class="empty-title">Ubicación sin coordenadas</p><p class="empty-subtitle text-secondary">Este lote aún no tiene una ubicación geográfica registrada.</p>
                        @can('lotes.update')<div class="empty-action"><a class="btn btn-primary" href="{{ route('lotes.edit', $lote) }}">Agregar coordenadas</a></div>@endcan
                    </div>
                @endif
            </section>
        </div>
        <div class="col-lg-4"><section class="card"><div class="card-header"><h2 class="card-title">Referencia del terreno</h2></div><div class="card-body">
            <div class="datagrid">
                <div class="datagrid-item"><div class="datagrid-title">Dirección / referencia</div><div class="datagrid-content">{{ $lote->ubicacion_visible }}</div></div>
                <div class="datagrid-item"><div class="datagrid-title">Superficie registrada</div><div class="datagrid-content">{{ $lote->superficie_etiqueta }}</div></div>
                <div class="datagrid-item"><div class="datagrid-title">Semilla / cultivo</div><div class="datagrid-content">{{ $lote->cultivo_etiqueta ?: 'Sin registrar' }}</div></div>
                <div class="datagrid-item"><div class="datagrid-title">Latitud</div><div class="datagrid-content">{{ $lote->latitud ?? 'Sin registrar' }}</div></div>
                <div class="datagrid-item"><div class="datagrid-title">Longitud</div><div class="datagrid-content">{{ $lote->longitud ?? 'Sin registrar' }}</div></div>
            </div>
        </div></section></div>
    </div>
    @include('lotes.tabler.actions')
@endsection
