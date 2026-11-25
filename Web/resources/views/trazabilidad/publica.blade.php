@extends('layouts.public-trazabilidad')
@section('title', 'Trazabilidad | AgroFusion')
@section('content')
@php($presentacion = \App\Support\PresentacionTrazabilidadPublica::class)
<header class="mb-4 trz-wrap">
    <div class="page-pretitle mb-2">Trazabilidad pública</div>
    <h1 class="h2">{{ $reporte['producto']['nombre'] ?? 'Producto con trazabilidad registrada' }}</h1>
    <p class="text-secondary mb-2">{{ $reporte['codigo'] }}</p>
    @if($reporte['producto']['cultivo'])<p>Cultivo: {{ $reporte['producto']['cultivo'] }}</p>@endif
    <a href="{{ route('trazabilidad.buscar') }}">Realizar otra búsqueda</a>
</header>
<div class="row g-3 mb-4">
    <section class="col-md-6" aria-labelledby="certificacion-titulo">
        <div class="card h-100"><div class="card-body">
            <h2 class="card-title" id="certificacion-titulo">Certificación</h2>
            <p class="fw-semibold">{{ $reporte['certificaciones']['estado'] === 'sin_certificacion_registrada' ? 'Sin certificación registrada' : 'Emisiones de certificación registradas' }}</p>
            <p class="text-secondary mb-0">La existencia de una emisión no acredita por sí sola la vigencia actual del producto.</p>
        </div></div>
    </section>
    <section class="col-md-6" aria-labelledby="blockchain-titulo">
        <div class="card h-100"><div class="card-body">
            <h2 class="card-title" id="blockchain-titulo">Respaldo blockchain</h2>
            <p class="fw-semibold">{{ $reporte['blockchain']['estado'] === 'sin_respaldo_registrado' ? 'Sin respaldo blockchain registrado' : 'Registros blockchain disponibles' }}</p>
            <p class="text-secondary mb-0">Estados guardados en el sistema. Esta consulta no realiza una verificación en vivo de la red.</p>
        </div></div>
    </section>
</div>
@if($reporte['origenes'])
<section class="card mb-4" aria-labelledby="origenes-titulo">
    <div class="card-body">
        <h2 class="card-title" id="origenes-titulo">Orígenes vinculados</h2>
        <ul class="mb-0">
            @foreach($reporte['origenes'] as $origen)<li class="trz-wrap">{{ $origen['nombre'] ?? 'Lote agrícola' }} · {{ $origen['codigo'] ?? 'Código no registrado' }}</li>@endforeach
        </ul>
    </div>
</section>
@endif
<section aria-labelledby="recorrido-titulo">
    <h2 class="h3" id="recorrido-titulo">Recorrido registrado</h2>
    <p class="text-secondary">Se muestran únicamente los vínculos disponibles. Las actividades describen el contexto del lote de origen; el orden de las secciones no acredita etapas completadas ni conexiones adicionales.</p>
    @foreach($reporte['etapas'] as $etapa)
        <section class="card mb-3" aria-labelledby="etapa-{{ $etapa['tipo'] }}">
            <div class="card-header"><h3 class="card-title" id="etapa-{{ $etapa['tipo'] }}">{{ $presentacion::texto($etapa['tipo']) }}</h3></div>
            <div class="card-body">
                @forelse($etapa['eventos'] as $evento)
                    <article class="trz-event">
                        <h4 class="h4">{{ $presentacion::texto($evento['tipo']) }}</h4>
                        @include('trazabilidad.campos', ['registro' => $evento])
                    </article>
                @empty
                    <p class="text-secondary mb-0">Sin información registrada para esta etapa.</p>
                @endforelse
            </div>
        </section>
    @endforeach
</section>
@if($reporte['rutas'])
<section class="card mb-4" aria-labelledby="envios-titulo">
    <div class="card-body">
        <h2 class="card-title" id="envios-titulo">Envíos vinculados</h2>
        @foreach($reporte['rutas'] as $ruta)
            <article class="trz-event">
                <h3 class="h4 trz-wrap">{{ $ruta['codigo'] ?? $ruta['referencia'] }}</h3>
                <p>{{ $presentacion::texto($ruta['origen']['tipo']) }} → {{ $presentacion::texto($ruta['destino']['tipo']) }}</p>
                @include('trazabilidad.campos', ['registro' => $ruta])
            </article>
        @endforeach
    </div>
</section>
@endif
<section class="card mb-4" aria-labelledby="emisiones-titulo">
    <div class="card-body">
        <h2 class="card-title" id="emisiones-titulo">Historial de certificaciones</h2>
        @forelse($reporte['certificaciones']['emisiones'] as $emision)
            <article class="trz-event">
                <h3 class="h4 trz-wrap">{{ $emision['codigo_certificado'] ?? 'Emisión sin código registrado' }}</h3>
                <dl class="trz-fields">
                    <div><dt>Ámbito</dt><dd>{{ $presentacion::texto($emision['ambito']) }}</dd></div>
                    <div><dt>Lote vinculado</dt><dd>{{ $emision['codigo_lote'] ?? 'No registrado' }}</dd></div>
                    <div><dt>Fecha de emisión</dt><dd>{{ $emision['fecha_emision'] ?? 'No registrada' }}</dd></div>
                    <div><dt>Resultado de la emisión</dt><dd>{{ $emision['resultado'] ?? 'No registrado' }}</dd></div>
                    <div><dt>Vigencia</dt><dd>{{ $emision['vigencia'] === 'no_determinada' ? 'No determinada: el registro no permite acreditar vigencia actual.' : $presentacion::texto($emision['vigencia']) }}</dd></div>
                </dl>
            </article>
        @empty
            <p class="text-secondary mb-0">Sin certificación registrada.</p>
        @endforelse
    </div>
</section>
@if($reporte['blockchain']['registros'])
<section class="card mb-4" aria-labelledby="registros-blockchain-titulo">
    <div class="card-body">
        <h2 class="card-title" id="registros-blockchain-titulo">Detalle del respaldo blockchain</h2>
        @foreach($reporte['blockchain']['registros'] as $registro)
            <article class="trz-event">
                <h3 class="h4 trz-wrap">{{ $registro['codigo_certificado'] ?? 'Emisión sin código registrado' }}</h3>
                <p class="fw-semibold">{{ $registro['confirmacion_registrada'] ? 'Confirmación registrada en el sistema' : 'Sin confirmación registrada' }}</p>
                <dl class="trz-fields">
                    <div><dt>Lote vinculado</dt><dd>{{ $registro['codigo_lote'] ?? 'No registrado' }}</dd></div>
                    <div><dt>Estado guardado</dt><dd>{{ match($registro['estado_registrado']) { 'pendiente' => 'Pendiente de confirmación', 'error' => 'Error registrado', 'rechazada' => 'Registro rechazado', 'omitida' => 'Registro omitido', 'certificada' => 'Certificada (estado guardado)', 'confirmado' => 'Confirmado (estado guardado)', default => 'Estado no disponible' } }}</dd></div>
                    <div><dt>Fuente</dt><dd>Registro local; sin verificación en vivo</dd></div>
                    @foreach(['hash_payload' => 'Hash de los datos certificados', 'hash_documento' => 'Hash del documento', 'hash_transaccion' => 'Hash de transacción', 'hash_bloque' => 'Hash del bloque', 'red' => 'Red', 'fecha_envio_registrada' => 'Envío registrado', 'fecha_confirmacion_registrada' => 'Confirmación registrada el', 'ultima_comprobacion_en' => 'Última comprobación en la red'] as $clave => $etiqueta)
                        <div><dt>{{ $etiqueta }}</dt><dd>{{ $registro[$clave] ?? 'No disponible' }}</dd></div>
                    @endforeach
                </dl>
            </article>
        @endforeach
    </div>
</section>
@endif
<section class="card" aria-labelledby="evidencias-titulo">
    <div class="card-body">
        <h2 class="card-title" id="evidencias-titulo">Evidencias públicas</h2>
        @forelse($reporte['evidencias'] as $evidencia)
            <figure class="trz-event mb-0">
                <a href="{{ $evidencia['url'] }}"><img class="trz-evidence" src="{{ $evidencia['url'] }}" alt="Evidencia revisada y aprobada para difusión pública" loading="lazy"></a>
                <figcaption class="text-secondary mt-2 trz-wrap">{{ $evidencia['referencia'] }} · Publicada: {{ $evidencia['fecha_publicacion'] }}</figcaption>
            </figure>
        @empty
            <p class="text-secondary mb-0">No hay evidencias públicas disponibles.</p>
        @endforelse
    </div>
</section>
<a class="trz-back" href="{{ route('trazabilidad.buscar') }}">Realizar otra búsqueda</a>
@endsection