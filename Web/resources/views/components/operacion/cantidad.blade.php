@props(['valor', 'unidad' => null])
<span {{ $attributes->class(['op-cantidad']) }}>
    @if($valor === null)<span class="text-muted">Sin cantidad registrada</span>
    @else{{ \App\Support\CosechaDecimal::mostrar($valor) }} <span class="op-cantidad__unidad">{{ filled($unidad) ? $unidad : 'Unidad sin registrar' }}</span>@endif
</span>
