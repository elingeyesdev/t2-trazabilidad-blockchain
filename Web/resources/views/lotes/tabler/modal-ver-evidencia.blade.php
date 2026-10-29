<div class="modal fade" id="modalVerEvidencia" tabindex="-1" role="dialog" aria-labelledby="modalVerEvidenciaTitulo" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered modal-lg" role="document">
        <div class="modal-content border-0 " style="border-radius: 14px; overflow: hidden;">
            <div class="modal-header border-0 py-3 px-4" >
                <h5 class="modal-title fw-semibold mb-0" id="modalVerEvidenciaTitulo">
                    <i class="ti ti-photo me-2"></i>Evidencia fotográfica
                </h5>
                <button type="button" class="btn-close text-body" data-bs-dismiss="modal" aria-label="Cerrar" style="opacity: .9;">

                </button>
            </div>
            <div class="modal-body px-4 py-4 text-center">
                <p class="text-secondary small mb-3" id="modalVerEvidenciaSubtitulo"></p>
                <img id="modalVerEvidenciaImg" alt="Evidencia" class="img-fluid rounded border " style="max-height: 70vh;">
            </div>
            <div class="modal-footer border-0 bg-light px-4 py-3 justify-content-between">
                <a href="#" target="_blank" rel="noopener" class="btn btn-outline-primary btn-sm" id="btnAbrirEvidenciaNueva">
                    <i class="ti ti-external-link me-1"></i> Abrir en pestaña nueva
                </a>
                <button type="button" class="btn btn-outline-secondary px-4" data-bs-dismiss="modal">Cerrar</button>
            </div>
        </div>
    </div>
</div>

@once
@push('scripts')
<script>
(function () {
    if (window.ModalVerEvidencia) return;

    const img = document.getElementById('modalVerEvidenciaImg');
    const subtitulo = document.getElementById('modalVerEvidenciaSubtitulo');
    const titulo = document.getElementById('modalVerEvidenciaTitulo');
    const link = document.getElementById('btnAbrirEvidenciaNueva');

    function abrir(url, etiqueta) {
        if (!url || !img) return;
        img.src = url;
        if (link) {
            link.href = url;
            link.style.display = '';
        }
        if (subtitulo) subtitulo.textContent = etiqueta || '';
        if (titulo) {
            titulo.textContent = etiqueta ? 'Evidencia: ' + etiqueta : 'Evidencia fotográfica';
        }
        if (window.jQuery) window.jQuery('#modalVerEvidencia').modal('show');
    }

    window.ModalVerEvidencia = { abrir: abrir };

    document.addEventListener('click', function (e) {
        const btn = e.target.closest('.btn-ver-evidencia');
        if (!btn) return;
        e.preventDefault();
        abrir(btn.getAttribute('data-url'), btn.getAttribute('data-titulo') || '');
    });
})();
</script>
@endpush
@endonce
