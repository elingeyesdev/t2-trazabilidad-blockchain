<form method="GET" action="{{ route('trazabilidad.buscar') }}">
    <label class="form-label" for="codigo">Código de trazabilidad</label>
    <div class="trz-search-row">
        <input class="form-control {{ !empty($error) ? 'is-invalid' : '' }}" type="text" id="codigo" name="codigo"
            value="{{ $codigo ?? '' }}" maxlength="64" required autocomplete="off" spellcheck="false"
            aria-describedby="codigo-ayuda{{ !empty($error) ? ' codigo-error' : '' }}" @if(!empty($error)) aria-invalid="true" @endif>
        <button class="btn btn-primary" type="submit">Consultar</button>
    </div>
    <p class="form-hint mt-2" id="codigo-ayuda">Escribe el código de la etiqueta: TRAZ-… o TRZ-… para un lote agrícola; TRZ-PDV-… para un producto de punto de venta. Se admiten códigos PDV con fecha o UUID.</p>
    @if(!empty($error))
        <p class="text-danger mt-2" id="codigo-error" role="alert">{{ $error }}</p>
    @endif
</form>