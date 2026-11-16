@if($lote->insumoSemilla)
    <div class="mb-3">
        <label class="font-weight-bold fw-semibold">Cantidad realmente consumida: {{ $lote->insumoSemilla->nombre }}</label>
        <input type="hidden" name="consumos[0][insumoid]" value="{{ $lote->insumosemillaid }}">
        <input type="hidden" name="consumos[0][almacenid]" value="{{ $lote->insumoSemilla->almacenid }}">
        <input type="number" name="consumos[0][cantidad]" class="form-control" min="0.001" step="0.001"
               value="{{ old('consumos.0.cantidad', $lote->getRawOriginal('cantidad_semilla_planificada')) }}"
               aria-label="Cantidad de semilla realmente consumida">
        <small class="text-muted">Use la unidad del insumo. Almacén #{{ $lote->insumoSemilla->almacenid }}.</small>
        @error('consumos.0.cantidad')<div class="text-danger small">{{ $message }}</div>@enderror
        @error('consumos.0.almacenid')<div class="text-danger small">{{ $message }}</div>@enderror
    </div>
@endif
