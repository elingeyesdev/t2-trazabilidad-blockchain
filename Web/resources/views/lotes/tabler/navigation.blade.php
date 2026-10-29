<nav class="mb-4" aria-label="Secciones del lote">
        <ul class="nav nav-tabs flex-wrap">
            @foreach(['show' => ['info-circle', 'Información del lote'], 'trazabilidad' => ['route', 'Trazabilidad'], 'ubicacion' => ['map-pin', 'Ubicación']] as $route => [$icon, $label])
                <li class="nav-item"><a class="nav-link {{ request()->routeIs('lotes.'.$route) ? 'active' : '' }}" href="{{ route('lotes.'.$route, $lote) }}" @if(request()->routeIs('lotes.'.$route)) aria-current="page" @endif><i class="ti ti-{{ $icon }} me-2" aria-hidden="true"></i>{{ $label }}</a></li>
            @endforeach
        </ul>
</nav>
