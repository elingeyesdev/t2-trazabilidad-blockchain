<ol class="breadcrumb mb-3" aria-label="Ubicación en el sistema">
    <li class="breadcrumb-item"><a href="{{ route('lotes.index') }}">Lotes</a></li>
    <li class="breadcrumb-item active" aria-current="page">{{ $lote->nombre }}</li>
</ol>
<div class="row g-3 align-items-center">
    <div class="col-auto"><span class="avatar avatar-lg lote-avatar"><i class="ti ti-plant-2" aria-hidden="true"></i></span></div>
    <div class="col">
        <div class="page-pretitle">{{ $sectionTitle }}</div>
        <h1 class="page-title">{{ $lote->nombre }}</h1>
        <div class="text-secondary mt-1">{{ $lote->cultivo_etiqueta ?: 'Cultivo sin registrar' }} <span class="mx-1">·</span> {{ $lote->codigo_trazabilidad ?: 'Lote #'.$lote->loteid }}</div>
    </div>
    <div class="col-12 col-md-auto"><x-tabler.lote-state :nombre="$lote->estadoTipo->nombre ?? 'Sin estado'" /></div>
</div>
