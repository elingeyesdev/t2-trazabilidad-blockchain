<dl class="trz-fields">
    @foreach(\App\Support\PresentacionTrazabilidadPublica::campos($registro) as $etiqueta => $valor)
        <div><dt>{{ $etiqueta }}</dt><dd>{{ $valor }}</dd></div>
    @endforeach
</dl>