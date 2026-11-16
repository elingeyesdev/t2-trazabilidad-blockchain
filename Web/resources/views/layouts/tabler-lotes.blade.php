<!DOCTYPE html>
<html lang="es" data-bs-theme="light">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>@yield('title', 'AgroFusion')</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
    @vite(['resources/css/tabler-lotes.css', 'resources/js/tabler-lotes.js'])
    @stack('styles')
    @vite('resources/css/agrofusion-ui.css')
</head>
@php
    extract(\App\Support\InterfazContexto::datos());
@endphp
<body class="ag-ui">
<a class="visually-hidden-focusable btn btn-primary" href="#contenido">Ir al contenido</a>
<div class="ag-overlay" id="agOverlay"></div>
<div class="ag-layout">
    @include('layouts.partials.menu-lateral')
    <div class="ag-main" id="agMain">
        @include('layouts.partials.barra-superior')
        <main class="ag-content" id="contenido" tabindex="-1">
            <div class="content-header">@yield('header')</div>
            @include('lotes.tabler.alerts')
            @yield('content')
        </main>
        <footer class="ag-footer">
            <span>&copy; {{ date('Y') }} <strong>AgroFusion</strong> · Sistema de Gestión Agrícola</span>
        </footer>
    </div>
</div>
@include('layouts.partials.shell-script')
@stack('modals')
@php
    // Run operational partials after the shared module has loaded its dependencies.
    $runtimeImport = app()->runningUnitTests() ? '' : 'import '.json_encode(\Illuminate\Support\Facades\Vite::asset('resources/js/tabler-lotes.js')).';';
    $pageScripts = str_replace('<script>', '<script type="module">'.$runtimeImport, $__env->yieldPushContent('scripts'));
@endphp
{!! $pageScripts !!}
@include('layouts.partials.graficos-tema')
</body>
</html>
