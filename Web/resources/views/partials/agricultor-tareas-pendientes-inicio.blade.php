@php
    $tareas = $tareasPendientes ?? [];
    $total = $totalTareasPendientes ?? count($tareas);
@endphp

@if($total > 0)
<div class="card mb-3 agricultor-tareas-card">
    <div class="card-body py-3">
        <button type="button"
                class="btn btn-link p-0 text-left border-0 bg-transparent w-100 text-body agricultor-tareas-card__trigger"
                data-toggle="modal"
                data-target="#modalAgricultorTareasInicio"
                style="text-decoration:none;">
            <div class="d-flex align-items-center justify-content-between" style="gap:.75rem;">
                <div class="d-flex align-items-center" style="gap:.65rem;">
                    <span class="agricultor-tareas-card__icon">
                        <i class="fas fa-clipboard-list"></i>
                    </span>
                    <div>
                        <strong class="agricultor-tareas-card__titulo">
                            Tienes {{ $total }} {{ $total === 1 ? 'tarea pendiente' : 'tareas pendientes' }}
                        </strong>
                        <span class="d-block text-muted" style="font-size:.78rem;">
                            Consulta y abre las actividades asignadas
                        </span>
                    </div>
                </div>
                <span class="agricultor-tareas-card__accion">Ver tareas <i class="fas fa-chevron-right ml-1" aria-hidden="true"></i></span>
            </div>
        </button>
    </div>
</div>

@include('partials.agricultor-tareas-pendientes-modal', [
    'modalId' => 'modalAgricultorTareasInicio',
    'tareas' => $tareas,
    'autoShow' => false,
])
@endif
