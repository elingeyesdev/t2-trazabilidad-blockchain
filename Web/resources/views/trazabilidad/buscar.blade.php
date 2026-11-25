@extends('layouts.public-trazabilidad')
@section('title', $titulo.' | AgroFusion')
@section('content')
<section class="trz-search" aria-labelledby="buscar-titulo">
    <div class="page-pretitle mb-2">Trazabilidad pública</div>
    <h1 class="h2 mb-3" id="buscar-titulo">{{ $titulo }}</h1>
    <p class="text-secondary mb-4">Consulta los registros disponibles del origen y recorrido de tu producto, sin iniciar sesión.</p>
    <div class="card">
        <div class="card-body">@include('trazabilidad.formulario')</div>
    </div>
    @if(!empty($error))
        <a class="trz-back" href="{{ route('trazabilidad.buscar') }}">Volver al buscador</a>
    @endif
</section>
@endsection