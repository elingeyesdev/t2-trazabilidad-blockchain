@php
    $actPend = $actividad_siembra_pendiente ?? null;
    $resumenSiembra = $resumen_siembra_completar ?? [];
@endphp
<div class="modal fade" id="modalCompletarSiembra" tabindex="-1" role="dialog" aria-labelledby="modalCompletarSiembraLabel" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered modal-lg" role="document">
        <div class="modal-content border-0 " style="border-radius: 14px; overflow: hidden;">
            <form method="POST" action="{{ route('lotes.siembra.completar.store', $lote) }}" enctype="multipart/form-data" id="formCompletarSiembraModal">
                @csrf
                <input type="hidden" name="return" value="{{ route('lotes.trazabilidad', $lote) }}">

                <div class="modal-header border-0 py-3 px-4" >
                    <h5 class="modal-title fw-semibold mb-0" id="modalCompletarSiembraLabel">
                        <i class="ti ti-plant-2 me-2"></i>Completar siembra
                    </h5>
                    <button type="button" class="btn-close text-body" data-bs-dismiss="modal" aria-label="Cerrar" style="opacity: .9;">

                    </button>
                </div>

                <div class="modal-body px-4 py-4">
                    <p class="text-secondary small mb-3">
                        Revise el resumen de la siembra programada. Luego suba una foto como evidencia para completar la actividad.
                    </p>

                    <div class="siembra-modal-resumen bg-light rounded p-3 mb-4">
                        <p class="small text-uppercase text-secondary fw-semibold mb-2">Resumen — solo lectura</p>
                        <dl class="row mb-0 small">
                            <dt class="col-sm-4 text-secondary">Lote</dt>
                            <dd class="col-sm-8 fw-semibold mb-2">{{ $lote->nombre }}</dd>

                            @if($lote->cultivo_etiqueta ?? $lote->cultivo?->nombre)
                                <dt class="col-sm-4 text-secondary">Semilla / cultivo</dt>
                                <dd class="col-sm-8 fw-semibold mb-2">{{ $lote->cultivo_etiqueta ?? $lote->cultivo?->nombre }}</dd>
                            @endif

                            @if($lote->ubicacion)
                                <dt class="col-sm-4 text-secondary">Dónde sembrar</dt>
                                <dd class="col-sm-8 fw-semibold mb-2">{{ $lote->ubicacion }}</dd>
                            @endif

                            <dt class="col-sm-4 text-secondary">Superficie</dt>
                            <dd class="col-sm-8 fw-semibold mb-2">{{ $lote->superficie_etiqueta ?? ($lote->superficie.' ha') }}</dd>

                            @if($lote->codigo_trazabilidad)
                                <dt class="col-sm-4 text-secondary">Código trazabilidad</dt>
                                <dd class="col-sm-8 fw-semibold mb-2">{{ $lote->codigo_trazabilidad }}</dd>
                            @endif

                            @if(!empty($actPend))
                                <dt class="col-sm-4 text-secondary">Actividad</dt>
                                <dd class="col-sm-8 fw-semibold mb-2">{{ $actPend['titulo'] ?? 'Siembra' }}</dd>
                                @if(!empty($actPend['responsable']))
                                    <dt class="col-sm-4 text-secondary">Responsable</dt>
                                    <dd class="col-sm-8 fw-semibold mb-2">{{ $actPend['responsable'] }}</dd>
                                @endif
                                @if(!empty($actPend['fechainicio']))
                                    <dt class="col-sm-4 text-secondary">Fecha programada</dt>
                                    <dd class="col-sm-8 fw-semibold mb-2">{{ $actPend['fechainicio'] }}</dd>
                                @endif
                            @endif
                        </dl>
                    </div>

                    @include('lotes.tabler.siembra-resumen-extendido', [
                        'resumen_siembra_completar' => $resumenSiembra,
                        'mapaId' => 'siembraModalMapa',
                        'mapaInitEvent' => '#modalCompletarSiembra',
                    ])

                    <hr class="my-3">

                    <label class="fw-semibold d-block mb-2">
                        <i class="ti ti-camera text-primary me-1"></i> Foto de evidencia <span class="text-danger">*</span>
                    </label>
                    @include('lotes.tabler.evidencia-foto-campo', [
                        'inputId' => 'siembraModalEvidenciaInput',
                        'btnId' => 'siembraModalEvidenciaBtn',
                        'previewWrapId' => 'siembraModalEvidenciaPreviewWrap',
                        'previewImgId' => 'siembraModalEvidenciaPreviewImg',
                        'previewNombreId' => 'siembraModalEvidenciaPreviewNombre',
                        'btnLabel' => 'Tomar o subir foto de la siembra',
                        'hint' => 'Muestre el surco sembrado, las semillas o el trabajo realizado.',
                    ])

                    <div class="mb-3 mt-3 mb-0">
                        <label class="fw-semibold small text-secondary" for="siembraModalObservaciones">Comentario opcional</label>
                        <textarea name="observaciones" id="siembraModalObservaciones" class="form-control" rows="2" maxlength="250"
                                  placeholder="Ej: Surcos 1-4, buen estado del suelo…">{{ old('observaciones') }}</textarea>
                    </div>
                </div>

                <div class="modal-footer border-0 bg-light px-4 py-3">
                    <button type="button" class="btn btn-outline-secondary px-4" data-bs-dismiss="modal">Cancelar</button>
                    <button type="submit" class="btn btn-primary px-4 fw-semibold" id="btnEnviarSiembraModal">
                        <i class="ti ti-send me-1"></i> Enviar evidencia y completar
                    </button>
                </div>
            </form>
        </div>
    </div>
</div>

@once
@push('scripts')
<script>
document.addEventListener('DOMContentLoaded', function () {
    if (window.AgrofusionEvidenciaFotoCampo) {
        window.AgrofusionEvidenciaFotoCampo(
            'siembraModalEvidenciaInput',
            'siembraModalEvidenciaBtn',
            'siembraModalEvidenciaPreviewWrap',
            'siembraModalEvidenciaPreviewImg',
            'siembraModalEvidenciaPreviewNombre'
        );
    }

    @if($errors->has('evidencia_foto') || $errors->has('observaciones'))
    if (window.jQuery) {
        window.jQuery('#modalCompletarSiembra').modal('show');
    }
    @endif
});
</script>
@endpush
@endonce
