@extends('layouts.app')
@section('title', 'Antecedente de certificación')
@section('page_title', 'Detalle del certificado')
@section('content')
@php($campo = $ambito === 'campo')
@php($producto = $campo ? $emision->lote : $emision->loteProduccionPedido)
<div class="d-flex flex-wrap justify-content-between align-items-center mb-3" style="gap:.5rem">
    <a class="btn btn-outline-secondary" href="{{ $campo ? route('lotes.certificados.index', $producto) : route('procesamiento.certificados.index', $producto) }}">Historial del lote</a>
    @if($emision->archivo_path)<a class="btn btn-success" href="{{ $campo ? route('certificaciones.archivo', $emision) : route('certificaciones-planta.archivo', $emision) }}">Descargar documento emitido</a>@endif
</div>
<div class="card"><div class="card-body">
@if($emision->datos_emision)
    @include('certificados.partials.instantanea', ['datos' => $emision->datos_emision])
@else
    <div class="alert alert-light border">Antecedente anterior sin instantánea histórica ni documento archivado. No se reconstruyen los datos originales con información actual.</div>
    <h2 class="h4">{{ $emision->codigo_certificado ?? 'Evaluación #'.$emision->getKey() }}</h2>
    <dl><dt>Fecha registrada</dt><dd>{{ ($campo ? $emision->fecha_certificacion : $emision->fecha_evaluacion)?->format('d/m/Y H:i:s') ?? 'No registrada' }}</dd>
    <dt>Resultado registrado</dt><dd>{{ $campo ? $emision->resultado : $emision->razon }}</dd>
    <dt>Emisor registrado</dt><dd>{{ ($campo ? $emision->usuarioid : $emision->inspector_usuarioid) ?? 'No registrado' }}</dd>
    <dt>Observaciones</dt><dd>{{ $emision->observaciones ?? 'Sin observaciones' }}</dd>
    <dt>Recomendaciones</dt><dd>{{ $emision->recomendaciones ?? 'Sin recomendaciones' }}</dd></dl>
@endif
</div></div>
@if($campo)@include('certificados.partials.integracion', ['cert' => $emision])@endif
@include('certificados.partials.nueva-emision', compact('producto', 'ambito'))
@endsection
