@props(['nombre'])
@php
    $slug = \App\Support\EstadoLoteCatalogo::slugFromNombre($nombre);
    $color = 'secondary';
@endphp
<span class="badge bg-{{ $color }}-lt">{{ $slug ? \App\Support\EstadoLoteCatalogo::label($slug) : $nombre }}</span>
