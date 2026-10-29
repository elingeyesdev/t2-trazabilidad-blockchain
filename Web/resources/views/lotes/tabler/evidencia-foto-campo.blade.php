@php
    $inputId = $inputId ?? 'evidenciaFotoInput';
    $btnId = $btnId ?? 'evidenciaFotoBtn';
    $previewWrapId = $previewWrapId ?? 'evidenciaFotoPreviewWrap';
    $previewImgId = $previewImgId ?? 'evidenciaFotoPreviewImg';
    $previewNombreId = $previewNombreId ?? 'evidenciaFotoPreviewNombre';
    $required = $required ?? true;
@endphp
<div class="evidencia-foto-campo">
    <input type="file"
           name="{{ $name ?? 'evidencia_foto' }}"
           id="{{ $inputId }}"
           accept="image/jpeg,image/jpg,image/png,image/webp"
           class="d-none"
           @if($required) required @endif>
    <div class="text-center mb-3">
        <button type="button" class="btn btn-evidencia-upload" id="{{ $btnId }}">
            <i class="ti ti-camera me-2"></i>{{ $btnLabel ?? 'Seleccionar foto de evidencia' }}
        </button>
        <p class="small text-secondary mt-2 mb-0">{{ $hint ?? 'JPG, PNG o WebP — máximo 5 MB' }}</p>
    </div>
    <div id="{{ $previewWrapId }}" class="evidencia-foto-preview text-center" style="display:none;">
        <img id="{{ $previewImgId }}" alt="Vista previa" class="img-fluid rounded border ">
        <p class="small text-secondary mt-2 mb-0" id="{{ $previewNombreId }}"></p>
    </div>
    @error($name ?? 'evidencia_foto')
        <div class="alert alert-danger small mt-2 mb-0">{{ $message }}</div>
    @enderror
</div>

@once

@push('scripts')
<script>
(function () {
    if (window.AgrofusionEvidenciaFotoCampo) return;
    window.AgrofusionEvidenciaFotoCampo = function (inputId, btnId, previewWrapId, previewImgId, previewNombreId) {
        var input = document.getElementById(inputId);
        var btn = document.getElementById(btnId);
        var wrap = document.getElementById(previewWrapId);
        var img = document.getElementById(previewImgId);
        var nombre = document.getElementById(previewNombreId);
        btn?.addEventListener('click', function () { input?.click(); });
        input?.addEventListener('change', function () {
            var file = input.files && input.files[0];
            if (!file) {
                if (wrap) wrap.style.display = 'none';
                if (img) img.removeAttribute('src');
                if (nombre) nombre.textContent = '';
                return;
            }
            if (!file.type.startsWith('image/')) {
                input.value = '';
                alert('Seleccione una imagen (JPG, PNG o WebP).');
                return;
            }
            var reader = new FileReader();
            reader.onload = function (e) {
                if (img) img.src = e.target.result;
                if (nombre) nombre.textContent = file.name;
                if (wrap) wrap.style.display = 'block';
            };
            reader.readAsDataURL(file);
        });
    };
})();
</script>
@endpush
@endonce
