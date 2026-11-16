@if(!empty($alertas) && $alertas->count())
<section class="card dashboard-notificaciones mb-4" aria-label="Notificación">
    <div class="dashboard-notificaciones__cabecera">
        <div class="dashboard-notificaciones__encabezado">
            <h2 class="dashboard-notificaciones__titulo">Notificación</h2>
            <span class="dashboard-notificaciones__cantidad">{{ $totalAlertas ?? $alertas->count() }} sin leer</span>
        </div>
        <form action="{{ route('notificaciones.descartar-todas') }}" method="POST" class="m-0">
            @csrf
            <button type="submit" class="dashboard-notificaciones__cerrar" title="Cerrar todas las notificaciones" aria-label="Cerrar todas las notificaciones">
                <span aria-hidden="true">&times;</span>
            </button>
        </form>
    </div>
    <ul class="dashboard-notificaciones__lista">
        @foreach($alertas as $alerta)
            <li class="dashboard-notificaciones__fila">
                @if($alerta->enlace)
                    <form action="{{ route('notificaciones.leer', $alerta) }}" method="POST" class="m-0">
                        @csrf
                        <button type="submit" class="dashboard-notificaciones__abrir" aria-label="Ver detalle: {{ $alerta->titulo }}">
                            <span class="dashboard-notificaciones__contenido">
                                <span class="dashboard-notificaciones__nombre">{{ $alerta->titulo }}</span>
                                @if($alerta->mensaje)
                                    <span class="dashboard-notificaciones__mensaje">{{ Str::limit($alerta->mensaje, 180) }}</span>
                                @endif
                            </span>
                            <span class="dashboard-notificaciones__accion">Ver detalle</span>
                        </button>
                    </form>
                @else
                    <div class="dashboard-notificaciones__contenido dashboard-notificaciones__contenido--estatico">
                        <span class="dashboard-notificaciones__nombre">{{ $alerta->titulo }}</span>
                        @if($alerta->mensaje)
                            <span class="dashboard-notificaciones__mensaje">{{ Str::limit($alerta->mensaje, 180) }}</span>
                        @endif
                    </div>
                @endif
            </li>
        @endforeach
    </ul>
</section>
@endif