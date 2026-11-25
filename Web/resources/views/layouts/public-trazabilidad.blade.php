<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <title>@yield('title', 'Trazabilidad | AgroFusion')</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    @vite('resources/css/agrofusion-ui.css')
    <style>
        .trz-public-page { max-width: 1040px; margin: auto; padding: 24px 20px 48px; }
        .trz-brand { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding-bottom: 20px; margin-bottom: 28px; border-bottom: 1px solid var(--tblr-border-color); }
        .trz-brand > a:first-child { font-size: 20px; font-weight: 600; color: var(--tblr-body-color); }
        .trz-search { max-width: 640px; margin: 40px auto; }
        .trz-search-row { display: flex; gap: 12px; align-items: start; }
        .trz-search-row input { min-width: 0; flex: 1; }
        .trz-wrap, .trz-fields dd, .trz-fields dt { overflow-wrap: anywhere; min-width: 0; }
        .trz-fields { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px 24px; margin: 0; }
        .trz-fields dt { font-size: 12px; font-weight: 500; color: var(--tblr-secondary-color, #526071); }
        .trz-fields dd { margin: 3px 0 0; }
        .trz-event + .trz-event { margin-top: 20px; padding-top: 20px; border-top: 1px solid var(--tblr-border-color); }
        .trz-evidence { width: 100%; height: auto; max-height: 400px; object-fit: contain; background: var(--tblr-body-bg); }
        .trz-back { display: inline-block; margin-top: 20px; }
        .ag-public :focus-visible { outline: 3px solid #23754b; outline-offset: 3px; }
        @media (max-width: 575px) {
            .trz-public-page { padding: 20px 16px 32px; }
            .trz-search { margin-top: 24px; }
            .trz-search-row { flex-direction: column; }
            .trz-search-row input, .trz-search-row button { width: 100%; }
            .trz-fields { grid-template-columns: minmax(0, 1fr); }
        }
    </style>
</head>
<body class="ag-ui ag-public">
    <main class="trz-public-page">
        <nav class="trz-brand" aria-label="Navegación pública">
            <a href="{{ route('trazabilidad.buscar') }}">AgroFusion</a>
            <a href="{{ route('trazabilidad.buscar') }}">Consultar trazabilidad</a>
        </nav>
        @yield('content')
    </main>
</body>
</html>