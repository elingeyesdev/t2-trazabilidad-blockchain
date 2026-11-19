@props(['valor', 'etiqueta', 'unidad' => null, 'detalle' => null])
<div {{ $attributes->class(['op-metrica']) }}>
    <div class="op-metrica__etiqueta">{{ $etiqueta }}</div>
    <div class="op-metrica__valor">{{ $valor }}@if($unidad)<span>{{ $unidad }}</span>@endif</div>
    @if($detalle)<div class="op-metrica__detalle">{{ $detalle }}</div>@endif
</div>
