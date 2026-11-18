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
        @php($existenciaSemilla = app(\App\Services\InventarioExistenciaService::class)->resumen($lote->insumoSemilla))
        @if($existenciaSemilla['partidas'] !== [])
            <label class="small mt-2" for="partida-semilla">Partida realmente utilizada</label>
            <select id="partida-semilla" name="consumos[0][partida]" class="form-control" required>
                <option value="">Selecciona una partida</option>
                @if(\App\Support\InventarioDecimal::unidades($existenciaSemilla['cantidad_sin_partida']) > 0)<option value="0" @selected(old('consumos.0.partida') === '0')>Sin partida histórica · sin fecha registrada</option>@endif
                @foreach($existenciaSemilla['partidas'] as $partida)
                    @php($valorPartida = $partida['materiaprimaloteid'] ? 'm:'.$partida['materiaprimaloteid'] : 'p:'.$partida['inventario_presentacion_loteid'])
                    <option value="{{ $valorPartida }}" @selected(old('consumos.0.partida') === $valorPartida) @disabled(!$partida['utilizable'] || \App\Support\InventarioDecimal::unidades($partida['cantidad_fisica']) === 0)>{{ $partida['referencia'] ?: 'Partida #'.($partida['materiaprimaloteid'] ?? $partida['inventario_presentacion_loteid']) }} · {{ $partida['fecha_vencimiento'] ?: 'Sin fecha registrada' }} · {{ str_replace('_', ' ', $partida['vencimiento_estado']) }}</option>
                @endforeach
            </select>
            @error('consumos.0.materiaprimaloteid')<div class="text-danger small">{{ $message }}</div>@enderror
            @error('consumos.0.inventario_presentacion_loteid')<div class="text-danger small">{{ $message }}</div>@enderror
        @endif
    </div>
@endif
