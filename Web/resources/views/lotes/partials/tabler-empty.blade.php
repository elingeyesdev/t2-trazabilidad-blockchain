<div class="empty">
    <div class="empty-icon"><i class="ti ti-plant-2" aria-hidden="true"></i></div>
    <p class="empty-title">{{ $filtrosActivos->isNotEmpty() ? 'No hay lotes que coincidan' : 'No hay lotes disponibles' }}</p>
    <p class="empty-subtitle text-secondary">{{ $filtrosActivos->isNotEmpty() ? 'Prueba con otro nombre o limpia los filtros.' : 'Aún no tienes lotes visibles. Consulta tus asignaciones.' }}</p>
    <div class="empty-action">
        @if($filtrosActivos->isNotEmpty())<a href="{{ route('lotes.index', ['filtros_abiertos' => 1]) }}" class="btn">Limpiar filtros</a>@endif
        @can('lotes.create')<a href="{{ route('lotes.create') }}" class="btn btn-primary">Crear primer lote</a>@endcan
    </div>
</div>
