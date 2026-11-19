@props(['titulo', 'descripcion' => null])
<div {{ $attributes->class(['op-encabezado']) }}>
    <div class="op-encabezado__texto">
        <h2>{{ $titulo }}</h2>
        @if($descripcion)<p>{{ $descripcion }}</p>@endif
    </div>
    @if($slot->isNotEmpty())<div class="op-acciones">{{ $slot }}</div>@endif
</div>
