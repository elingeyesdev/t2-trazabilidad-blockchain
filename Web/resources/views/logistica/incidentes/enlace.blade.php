@if(!(\App\Support\UsuarioRol::esMinorista(auth()->user()) && in_array($tipoAfectado, ['distribucion', 'traslado'], true)))
<div class="op-acciones mb-3">
    @can('incidentes.view')<a class="btn btn-outline-secondary btn-sm" href="{{ route('logistica.incidentes.index', ['afectado_tipo' => $tipoAfectado, 'afectado_id' => $idAfectado]) }}">Consultar incidencias</a>@endcan
    @can('incidentes.create')<a class="btn btn-outline-secondary btn-sm" href="{{ route('logistica.incidentes.create', ['afectado_tipo' => $tipoAfectado, 'afectado_id' => $idAfectado]) }}">Reportar problema</a>@endcan
</div>
@endif
