@extends('layouts.tabler-lotes')
@section('title', 'Información del lote | AgroFusion')
@section('header')
    @include('lotes.tabler.header', ['sectionTitle' => 'Información del lote'])
@endsection
@section('content')
    @include('lotes.tabler.navigation')
    <div class="row g-3">
        <div class="col-lg-8">
            <section class="card h-100">
                <div class="card-header"><h2 class="card-title">Datos del lote</h2></div>
                <div class="card-body">
                    <div class="datagrid">
                        <div class="datagrid-item"><div class="datagrid-title">Responsable</div><div class="datagrid-content">{{ trim(($lote->usuario->nombre ?? '').' '.($lote->usuario->apellido ?? '')) ?: 'Sin asignar' }}</div></div>
                        <div class="datagrid-item"><div class="datagrid-title">Semilla / cultivo</div><div class="datagrid-content">{{ $lote->cultivo_etiqueta ?: 'Sin registrar' }}</div></div>
                        <div class="datagrid-item"><div class="datagrid-title">Superficie</div><div class="datagrid-content">{{ $lote->superficie_etiqueta }}</div></div>
                        <div class="datagrid-item"><div class="datagrid-title">Fecha de siembra</div><div class="datagrid-content">{{ $lote->fechasiembra ? \Carbon\Carbon::parse($lote->fechasiembra)->format('d/m/Y') : 'No registrada' }}</div></div>
                        <div class="datagrid-item"><div class="datagrid-title">Código de trazabilidad</div><div class="datagrid-content"><code>{{ $lote->codigo_trazabilidad ?: 'Sin código' }}</code></div></div>
                        <div class="datagrid-item"><div class="datagrid-title">Identificador del lote</div><div class="datagrid-content">#{{ $lote->loteid }}</div></div>
                    </div>
                    <hr class="my-4">
                    <div class="datagrid-title">Dirección / referencia</div>
                    <p class="mb-2">{{ $lote->ubicacion_visible }}</p>
                    <a href="{{ route('lotes.ubicacion', $lote) }}" class="btn btn-sm"><i class="ti ti-map-pin me-2" aria-hidden="true"></i>Consultar ubicación</a>
                    @if($lote->imagenurl)<img class="img-fluid rounded mt-4 lote-photo" src="{{ $lote->imagenurl }}" alt="Foto del lote {{ $lote->nombre }}">@endif
                </div>
            </section>
        </div>
        <div class="col-lg-4">
            <section class="card h-100">
                <div class="card-header"><h2 class="card-title">Resumen de actividad</h2></div>
                <div class="list-group list-group-flush">
                    @foreach(['Actividades completadas' => $estadisticas['actividades_completadas'], 'Actividades pendientes' => $estadisticas['actividades_pendientes'], 'Aplicaciones de insumos' => $estadisticas['total_insumos'], 'Cosechas registradas' => $estadisticas['total_cosechas'], 'Producción acumulada' => number_format($estadisticas['produccion_total'], 0).' kg', 'Días desde la siembra' => $estadisticas['dias_desde_siembra'] ?? '—'] as $label => $value)
                        <div class="list-group-item d-flex justify-content-between gap-3"><span class="text-secondary">{{ $label }}</span><strong>{{ $value }}</strong></div>
                    @endforeach
                </div>
                <div class="card-footer"><a href="{{ route('lotes.trazabilidad', $lote) }}" class="btn btn-primary w-100"><i class="ti ti-route me-2" aria-hidden="true"></i>Ver trazabilidad del lote</a></div>
            </section>
        </div>
    </div>
    @include('lotes.tabler.actions')
@endsection
