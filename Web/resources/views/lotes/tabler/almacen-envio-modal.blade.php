@php
    $modalId = $modalId ?? ('modalAlmacenes-' . ($sectionId ?? 'almacenSection'));
    $mapaId = $mapaId ?? ('mapaAlmacenes-' . ($sectionId ?? 'almacenSection'));
    $etiquetaAmbito = $etiquetaAmbito ?? 'agrícola';
@endphp

<div class="modal fade" id="{{ $modalId }}" tabindex="-1" role="dialog" aria-labelledby="{{ $modalId }}Label" aria-hidden="true">
    <div class="modal-dialog modal-xl modal-dialog-scrollable" role="document">
        <div class="modal-content">
            <div class="modal-header bg-light text-body">
                <h5 class="modal-title" id="{{ $modalId }}Label">
                    <i class="ti ti-building-warehouse me-2"></i>Buscar almacén {{ $etiquetaAmbito }}
                </h5>
                <button type="button" class="btn-close text-body" data-bs-dismiss="modal" aria-label="Cerrar">

                </button>
            </div>
            <div class="modal-body p-0">
                <ul class="nav nav-tabs almacen-modal-tabs px-3 pt-2" role="tablist">
                    <li class="nav-item">
                        <a class="nav-link active" id="{{ $modalId }}-tab-lista" data-bs-toggle="tab" href="#{{ $modalId }}-lista" role="tab">
                            <i class="ti ti-list me-1"></i> Lista
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" id="{{ $modalId }}-tab-mapa" data-bs-toggle="tab" href="#{{ $modalId }}-mapa" role="tab">
                            <i class="ti ti-map-2 me-1"></i> Ver en mapa
                        </a>
                    </li>
                </ul>

                <div class="tab-content">
                    <div class="tab-pane fade show active p-3" id="{{ $modalId }}-lista" role="tabpanel">
                        <div class="row mb-3">
                            <div class="col-md-6">
                                <label class="small fw-semibold text-secondary mb-1" for="{{ $modalId }}-filtro-nombre">
                                    <i class="ti ti-search me-1"></i> Filtrar por nombre
                                </label>
                                <input type="search" class="form-control form-control-sm" id="{{ $modalId }}-filtro-nombre"
                                       placeholder="Nombre, tipo o ubicación…" autocomplete="off">
                            </div>
                            <div class="col-md-3">
                                <label class="small fw-semibold text-secondary mb-1" for="{{ $modalId }}-filtro-cap-min">
                                    Capacidad disp. mín. (kg)
                                </label>
                                <input type="number" min="0" step="1" class="form-control form-control-sm" id="{{ $modalId }}-filtro-cap-min"
                                       placeholder="Ej: 1000">
                            </div>
                            <div class="col-md-3">
                                <label class="small fw-semibold text-secondary mb-1" for="{{ $modalId }}-filtro-cap-max">
                                    Capacidad disp. máx. (kg)
                                </label>
                                <input type="number" min="0" step="1" class="form-control form-control-sm" id="{{ $modalId }}-filtro-cap-max"
                                       placeholder="Sin límite">
                            </div>
                        </div>
                        <div class="row">
                            <div class="col-lg-7">
                                <p class="small text-secondary mb-2" id="{{ $modalId }}-resultados">Cargando almacenes…</p>
                                <div class="almacen-modal-lista" id="{{ $modalId }}-lista-items"></div>
                                <div class="text-center py-4 text-secondary d-none" id="{{ $modalId }}-sin-resultados">
                                    <i class="ti ti-inbox ti-2x mb-2 opacity-25 d-block"></i>
                                    No hay almacenes que coincidan con los filtros.
                                </div>
                            </div>
                            <div class="col-lg-5 mt-3 mt-lg-0">
                                <div class="almacen-modal-preview-panel" id="{{ $modalId }}-preview-panel" aria-live="polite">
                                    <p class="text-secondary small mb-0">
                                        <i class="ti ti-mouse-pointer me-1"></i>
                                        Pase el cursor sobre un almacén o haga clic para ver la previsualización.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="tab-pane fade p-3" id="{{ $modalId }}-mapa" role="tabpanel">
                        <p class="small text-secondary mb-2">
                            <i class="ti ti-hand-pointer me-1"></i>
                            Mapa con todos los almacenes {{ $etiquetaAmbito }}s. Haga clic en un pin para seleccionarlo.
                        </p>
                        <div class="almacen-mapa-wrap position-relative">
                            <div id="{{ $mapaId }}" class="almacen-mapa-modal"></div>
                            <div class="almacen-mapa-flash" id="{{ $mapaId }}-flash"></div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cerrar</button>
            </div>
        </div>
    </div>
</div>
