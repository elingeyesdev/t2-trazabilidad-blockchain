@php
    $modalId = $modalId ?? 'modalAgricultorTareasInicio';
    $tareas = $tareas ?? [];
    $autoShow = $autoShow ?? false;
    $marcarVistas = $marcarVistas ?? false;
    $clavesJson = json_encode(array_column($tareas, 'clave'));
    $scrimId = $modalId.'Scrim';
@endphp

@if(! empty($tareas))
<div class="login-notif-scrim ag-tareas-flotante-scrim" id="{{ $scrimId }}" aria-hidden="true"></div>

<div class="modal fade login-notif-modal-root ag-tareas-flotante" id="{{ $modalId }}" tabindex="-1" role="dialog"
     aria-labelledby="{{ $modalId }}Titulo" aria-describedby="{{ $modalId }}Ayuda" aria-hidden="true"
     data-backdrop="false" data-keyboard="true"
     @if($marcarVistas)
         data-login-notif-alcance="agricultor" data-login-notif-claves="{{ $clavesJson }}"
     @endif>
    <div class="modal-dialog modal-dialog-centered modal-lg" role="document">
        <div class="modal-content login-notif-modal login-notif-modal--agricultor">
            <div class="modal-header border-0 login-notif-modal__head">
                <div class="login-notif-modal__head-inner">
                    <span class="ag-tareas-flotante__categoria">Actividades de campo</span>
                    <h5 class="modal-title mb-0" id="{{ $modalId }}Titulo">
                        @if(count($tareas) === 1)
                            Tarea pendiente en campo
                        @else
                            {{ count($tareas) }} tareas pendientes en campo
                        @endif
                    </h5>
                </div>
                <button type="button" class="close" data-dismiss="modal" aria-label="Cerrar">
                    <span aria-hidden="true">&times;</span>
                </button>
            </div>
            <div class="modal-body login-notif-modal__body">
                <p class="ag-tareas-flotante__ayuda" id="{{ $modalId }}Ayuda">Consulta el trabajo asignado y registra el resultado con una foto al terminar.</p>
                <ul class="login-notif-modal__lista">
                    @foreach($tareas as $row)
                    <li class="login-notif-modal__item">
                        <div class="login-notif-modal__item-body">
                            <span class="login-notif-modal__codigo">
                                {{ $row['titulo'] }}
                            </span>
                            <span class="login-notif-modal__meta">
                                {{ $row['lote'] }}
                                @if(!empty($row['prioridad']))
                                    <span class="ag-tareas-flotante__prioridad">· Prioridad {{ mb_strtolower($row['prioridad']) }}</span>
                                @endif
                            </span>
                        </div>
                        <a href="{{ $row['url'] }}" class="btn btn-sm btn-outline-primary login-notif-modal__cta" aria-label="Abrir {{ $row['titulo'] }}">
                            Abrir <i class="fas fa-arrow-right ml-1" aria-hidden="true"></i>
                        </a>
                    </li>
                    @endforeach
                </ul>
            </div>
            <div class="modal-footer border-0 login-notif-modal__foot d-flex justify-content-between align-items-center">
                <a href="{{ route('actividades.index') }}" class="btn btn-sm login-notif-modal__btn-secondary">
                    <i class="fas fa-list mr-1"></i> Mis actividades
                </a>
                <button type="button" class="btn btn-sm login-notif-modal__btn-cerrar" data-dismiss="modal">Entendido</button>
            </div>
        </div>
    </div>
</div>

@push('scripts')
<script>
document.addEventListener('DOMContentLoaded', function () {
    var modalEl = document.getElementById(@json($modalId));
    var scrimEl = document.getElementById(@json($scrimId));
    if (!window.jQuery || !modalEl || !scrimEl) return;
    var $modal = window.jQuery(modalEl);
    $modal.on('show.bs.modal', function () {
        scrimEl.classList.add('is-visible');
        document.body.classList.add('modal-open', 'login-notif-modal-open', 'ag-tareas-flotante-open');
    }).on('hidden.bs.modal', function () {
        scrimEl.classList.remove('is-visible');
        document.body.classList.remove('modal-open', 'login-notif-modal-open', 'ag-tareas-flotante-open');
    });
    scrimEl.addEventListener('click', function () { $modal.modal('hide'); });
    @if($autoShow)
    $modal.modal({ backdrop: false, keyboard: true, show: true });
    @endif
});
</script>
@endpush
@endif
