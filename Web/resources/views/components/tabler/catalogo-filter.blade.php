@props(['name', 'label', 'value' => '', 'selectedLabel' => '', 'endpoint', 'params' => []])
<div data-catalogo-filter data-endpoint="{{ $endpoint }}" data-params="{{ json_encode($params) }}" data-title="{{ $label }}">
    <label class="form-label" for="catalogo-{{ $name }}">{{ $label }}</label>
    <input type="hidden" name="{{ $name }}" value="{{ $value }}">
    <div class="input-group">
        <button id="catalogo-{{ $name }}" type="button" class="form-control text-start text-truncate" data-catalogo-open aria-haspopup="dialog">
            <span data-catalogo-label>{{ $selectedLabel ?: 'Todos' }}</span>
        </button>
        <button type="button" class="btn btn-icon" data-catalogo-clear aria-label="Quitar filtro {{ $label }}"><i class="ti ti-x" aria-hidden="true"></i></button>
    </div>
</div>
@once
    @push('modals')
        <div class="modal fade" id="catalogoModal" tabindex="-1" aria-labelledby="catalogoTitulo" aria-hidden="true">
            <div class="modal-dialog modal-dialog-centered"><div class="modal-content">
                <div class="modal-header">
                    <h2 class="modal-title" id="catalogoTitulo">Seleccionar</h2>
                    <button class="btn-close" type="button" data-bs-dismiss="modal" aria-label="Cerrar"></button>
                </div>
                <div class="modal-body">
                    <label class="form-label" for="catalogoBuscar">Buscar por nombre</label>
                    <input id="catalogoBuscar" type="search" class="form-control mb-3" autocomplete="off">
                    <div id="catalogoResultados" class="catalogo-resultados list-group" aria-live="polite"></div>
                </div>
                <div class="modal-footer justify-content-between">
                    <button type="button" class="btn" id="catalogoAnterior">Anterior</button>
                    <span id="catalogoPagina" class="text-secondary"></span>
                    <button type="button" class="btn" id="catalogoSiguiente">Siguiente</button>
                </div>
            </div></div>
        </div>
    @endpush
@endonce
