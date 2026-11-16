<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title>@yield('title', 'AgroFusion | Panel')</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">

    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css">



    @stack('styles')
    @include('partials.estilos-kpi-ejecutivo')
    @include('partials.estilos-ejecutivo-global')
    @include('dashboard.partials.estilos-dash-ejecutivo')
    @include('partials.small-box-footer-styles')
    @include('partials.login-notificacion-estilos')
    @vite('resources/css/agrofusion-ui.css')
</head>

@php
    extract(\App\Support\InterfazContexto::datos());
@endphp

<body class="ag-ui">

<div class="ag-overlay" id="agOverlay"></div>

<div class="ag-layout">

    {{-- ═══════════════ SIDEBAR ═══════════════ --}}
    @include('layouts.partials.menu-lateral')
    {{-- END SIDEBAR --}}

    {{-- ═══════════════ MAIN ═══════════════ --}}
    <div class="ag-main" id="agMain">

        {{-- TOPBAR --}}
        @include('layouts.partials.barra-superior')
        {{-- END TOPBAR --}}

        {{-- CONTENT --}}
        <main class="ag-content">
            <div class="content-header">
                <div class="row align-items-center">
                    <div class="col">
                        <h1 class="m-0">@yield('page_title', 'Dashboard')</h1>
                    </div>
                </div>
            </div>

            @include('partials.flash-messages')

            @yield('content')
        </main>

        @include('partials.modal-bienvenida')
        @include('partials.modal-aviso')
        @include('partials.modal-confirmar-accion')
        @include('partials.flash-error-modal')
        @include('partials.transportista-asignacion-login-modal')
        @include('partials.operario-planta-tarea-login-modal')
        @include('partials.agricultor-actividad-login-modal')
        @include('partials.jefe-agricultor-envio-login-modal')
        @include('partials.mayorista-pedido-login-modal')
        @include('partials.minorista-envio-login-modal')
        @include('partials.jefe-planta-traslado-login-modal')
        @include('partials.login-notificacion-mount')
        @once
            @include('partials.selector-catalogo-assets')
            @include('partials.selector-catalogo-modal')
            @include('partials.modal-vehiculo-carga-preview')
        @endonce

        {{-- FOOTER --}}
        <footer class="ag-footer">
            <span>&copy; {{ date('Y') }} <strong>AgroFusion</strong> · Sistema de Gestión Agrícola</span>
            <span>v1.0.0</span>
        </footer>

    </div>
    {{-- END MAIN --}}

</div>

<script src="https://code.jquery.com/jquery-3.6.4.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>

@include('layouts.partials.shell-script')

@include('partials.filtros-ui-script')

@stack('scripts')
@include('layouts.partials.graficos-tema')
</body>
</html>
