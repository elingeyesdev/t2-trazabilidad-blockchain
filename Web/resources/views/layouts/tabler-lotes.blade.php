<!DOCTYPE html>
<html lang="es" data-bs-theme="light">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>@yield('title', 'Lotes | AgroFusion')</title>
    @vite(['resources/css/tabler-lotes.css', 'resources/js/tabler-lotes.js'])
    @stack('styles')
</head>
<body>
<a class="visually-hidden-focusable btn btn-primary" href="#contenido">Ir al contenido</a>
<div class="page">
    <header class="navbar navbar-expand-xl bg-white border-bottom">
        <div class="container-xl">
            <a class="navbar-brand text-primary" href="{{ route('dashboard') }}">
                <i class="ti ti-plant-2 me-2" aria-hidden="true"></i>AgroFusion
            </a>
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#menuLotes" aria-controls="menuLotes" aria-expanded="false" aria-label="Abrir menú">
                <span class="navbar-toggler-icon"></span>
            </button>
            <div class="collapse navbar-collapse" id="menuLotes">
                <nav class="navbar-nav" aria-label="Navegación principal">
                    <a class="nav-link" href="{{ route('dashboard') }}"><i class="ti ti-home me-2" aria-hidden="true"></i>Inicio</a>
                    @can('lotes.view')
                        <a class="nav-link active" href="{{ route('lotes.index') }}" aria-current="page"><i class="ti ti-plant-2 me-2" aria-hidden="true"></i>Lotes</a>
                        <a class="nav-link" href="{{ route('lotes.mapa') }}"><i class="ti ti-map me-2" aria-hidden="true"></i>Mapa de lotes</a>
                        <a class="nav-link" href="{{ route('actividades.index') }}"><i class="ti ti-checklist me-2" aria-hidden="true"></i>Actividades</a>
                        <a class="nav-link" href="{{ route('actividades.calendario') }}"><i class="ti ti-calendar me-2" aria-hidden="true"></i>Calendario</a>
                    @endcan
                </nav>
                <div class="dropdown ms-xl-auto mt-2 mt-xl-0">
                    <button class="btn btn-ghost-secondary dropdown-toggle" type="button" data-bs-toggle="dropdown" aria-expanded="false">
                        <i class="ti ti-user me-2" aria-hidden="true"></i>{{ auth()->user()->nombre }}
                    </button>
                    <div class="dropdown-menu dropdown-menu-end">
                        <form method="POST" action="{{ route('logout') }}">
                            @csrf
                            <button type="submit" class="dropdown-item"><i class="ti ti-logout me-2" aria-hidden="true"></i>Cerrar sesión</button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    </header>
    <main class="page-wrapper" id="contenido" tabindex="-1">
        <div class="page-header"><div class="container-xl">@yield('header')</div></div>
        <div class="page-body"><div class="container-xl">
            @include('lotes.tabler.alerts')
            @yield('content')
        </div></div>
    </main>
</div>
@stack('modals')
@php
    // Run operational partials after the shared module has loaded its dependencies.
    $runtimeImport = app()->runningUnitTests() ? '' : 'import '.json_encode(\Illuminate\Support\Facades\Vite::asset('resources/js/tabler-lotes.js')).';';
    $pageScripts = str_replace('<script>', '<script type="module">'.$runtimeImport, $__env->yieldPushContent('scripts'));
@endphp
{!! $pageScripts !!}
</body>
</html>
