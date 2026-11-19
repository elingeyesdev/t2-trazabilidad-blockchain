    <aside class="ag-sidebar" id="agSidebar">

        {{-- Logo --}}
        <a href="{{ route('dashboard') }}" class="ag-brand">
            <div class="ag-brand-icon">
                <img src="{{ asset('images/agrofusion-logo.jpeg') }}" alt="AgroFusion">
            </div>
            <div class="ag-brand-text">
                <span class="ag-brand-name">AgroFusion</span>
                <span class="ag-brand-sub">Panel de trazabilidad</span>
            </div>
        </a>

        {{-- User panel --}}
        <div class="ag-sb-user">
            <img src="{{ $userImg }}" alt="Avatar" class="ag-sb-user-avatar"
                 data-avatar-fallback="{{ $userImgFallback }}"
                 onerror="if(this.dataset.avatarFallback){this.onerror=null;this.src=this.dataset.avatarFallback;}">
            <div class="ag-sb-user-info">
                <span class="ag-sb-user-name">{{ $userFull }}</span>
                <span class="ag-sb-user-role">{{ ucfirst($userRole) }}</span>
            </div>
        </div>

        {{-- Navigation --}}
        <nav class="ag-sb-nav">
            <ul class="ag-nav-ul">

                {{-- Dashboard --}}
                <li class="ag-nav-li">
                    <a href="{{ route('dashboard') }}"
                       class="ag-nav-a {{ request()->routeIs('dashboard') && !request()->routeIs('dashboard.panel-*') ? 'active' : '' }}">
                        <i class="ag-nav-icon fas fa-home"></i>
                        <span class="ag-nav-text">Inicio</span>
                    </a>
                </li>

                @php
                    $puedeAlmacenAgricola = $isAdmin || ($authUser && $authUser->hasRole('agricultor')) || $esJefeAgr;
                    $puedeAlmacenMayorista = $isAdmin || \App\Support\UsuarioRol::esMayorista($authUser);
                    $puedeMenuMayorista = $puedeAlmacenMayorista;
                    $mayMenuOpen = request()->routeIs('almacen-mayorista.*');
                    $enPedidosDist = request()->routeIs('punto-venta.pedidos.*') && ! request()->routeIs('punto-venta.rutas.*');
                    $ctxPedidosDist = request()->query('ctx');
                    $esFlujoSolicitudMinorista = request()->routeIs(
                        'punto-venta.pedidos.create',
                        'punto-venta.pedidos.store'
                    ) || $ctxPedidosDist === 'pdv';
                    $esBandejaMayoristaNav = request()->routeIs('punto-venta.pedidos.*')
                        && ! request()->routeIs('punto-venta.rutas.*')
                        && ($ctxPedidosDist === 'mayorista'
                            || (\App\Support\UsuarioRol::esMayorista($authUser) && ! \App\Support\UsuarioRol::esMinorista($authUser) && $ctxPedidosDist !== 'pdv'));
                    $pedidosEnSeccionPdv = $enPedidosDist && ($esMinoristaOperativo || $esFlujoSolicitudMinorista);
                    $pedidosEnSeccionMayorista = $enPedidosDist && ! $pedidosEnSeccionPdv && ($esMayoristaOperativo || ($isAdmin && $puedeMenuMayorista) || $esBandejaMayoristaNav);
                    $mayMenuOpen = $mayMenuOpen || $pedidosEnSeccionMayorista;
                    $almAgrOpen = request()->routeIs('almacen-agricola.*');
                    $almPlaOpen = request()->routeIs('almacen-planta.*');
                    $almMayOpen = request()->routeIs('almacen-mayorista.*');
                    $prodAgrOpen = request()->routeIs('producciones.*', 'climas.*');
                    if (! ($esJefeAgr && ! $isAdmin)) {
                    }
                    $prodPlaMenuOpen = request()->routeIs('procesos-planta.*', 'plantillas-transformacion.*', 'maquinas-planta.*', 'variables-estandar.*', 'procesamiento.*', 'tareas-planta.*', 'certificaciones-planta.*', 'produccion-planta.catalogos.*');
                    $envListadoActivo = request()->routeIs(
                        'logistica.asignaciones.listado',
                        'logistica.asignaciones.show',
                        'logistica.asignaciones.edit',
                        'pedidos.index',
                        'pedidos.show',
                        'pedidos.edit',
                        'pedidos.create',
                        'envios.mandar',
                        'envios.crear'
                    ) && ! request()->routeIs('logistica.rutas-tiempo-real.*', 'logistica.documentos.*');
                    $showProdAgricola = ! $esPlantaOperativo && ! $esTransportistaOperativo && ! $esMayoristaOperativo && (
                        $isAdmin
                        || $esJefeAgr
                        || ($authUser && $authUser->hasRole('agricultor'))
                        || auth()->user()?->canany(['lotes.view','lotes.create','lotes.update','lotes.delete'])
                        || auth()->user()?->can('certificaciones.view')
                        || auth()->user()?->canany(['inventario.view','inventario.create','inventario.update','inventario.delete'])
                        || $puedeAlmacenAgricola
                    );
                    $envPerm = [
                        'envios.view', 'envios.create', 'envios.admin.view',
                        'vehiculos.view', 'transportistas.view', 'direcciones.view',
                        'pedidos.view',
                        'asignaciones.view', 'rutas_multi.view', 'rutas_multi.create',
                        'documentos.view', 'incidentes.view',
                    ];
                    $puedeReportesLogistica = $isAdmin;
                    $puedeSubmenuEnviosScoped = \App\Support\RutaTiempoRealAcceso::puedeAccederModulo($authUser)
                        || \App\Support\DocumentoEntregaAcceso::puedeAccederModulo($authUser);
                    $logMasOpen = request()->routeIs('envios.reportes-distribucion');
                    $catalogoLogisticaOpen = request()->routeIs('envios.catalogos.*');
                    $catalogoTipoActivo = $catalogoLogisticaOpen ? request()->route('tipo') : null;
                    $esJefePlantaNav = $authUser && \App\Support\UsuarioRol::esJefePlanta($authUser);
                    $usaEnviosEnSeccionRol = ($esJefePlantaNav || $esJefeAgr || $esMayoristaOperativo) && ! $isAdmin;
                    $envOpen = request()->routeIs(
                        'envios.*',
                        'pedidos.create',
                        'pedidos.show',
                        'pedidos.edit',
                        'logistica.asignaciones.*',
                        'logistica.documentos.*',
                        'logistica.rutas-tiempo-real.*'
                    ) || $logMasOpen || request()->routeIs('pedidos.index');
                    $envPlantaOpen = ($envOpen || $catalogoLogisticaOpen) && ($esJefePlantaNav || $esPlantaOperativo);
                    $envAgrOpen = ($envOpen || $catalogoLogisticaOpen) && $esJefeAgr;
                    $envMayOpen = ($envOpen || $catalogoLogisticaOpen) && $esMayoristaOperativo;
                    $puedeEnvios = $isAdmin || ($authUser && $authUser->hasAnyPermission($envPerm));
                    $showOperLogistica = $isAdmin || $esTransportistaOperativo || (
                        $puedeEnvios && ! $esPlantaOperativo && ! $esAgricultorOperativo && ! $usaEnviosEnSeccionRol
                    );
                    $showProdPlantaSection = $isAdmin || $esPlantaOperativo || ($esJefePlantaNav && ! $isAdmin);
                    $puedeProdPlanta = $isAdmin || $esPlantaOperativo || $esJefePlantaNav;
                    // OPP-07: operario no ve administración de almacén / movimientos generales
                    $puedeAlmacenPlanta = $isAdmin || $esJefePlantaNav;
                @endphp

                {{-- TEMPORAL (solo UX): el admin no ve las secciones operativas en el sidebar. No afecta autorización backend. --}}
                @if(! $isAdmin)
                @if($showProdAgricola)
                <span class="ag-nav-label">Producción agrícola</span>

                @can('panel_agricultor.view')
                @if($esJefeAgr || $isAdmin)
                <li class="ag-nav-li">
                    <a href="{{ route('dashboard.panel-agricola') }}" class="ag-nav-a {{ request()->routeIs('dashboard.panel-agricola') ? 'active' : '' }}">
                        <i class="ag-nav-icon fas fa-tractor"></i>
                        <span class="ag-nav-text">Panel Agrícola</span>
                    </a>
                </li>
                @endif
                @endcan

                {{-- Lotes & Actividades --}}
                @canany(['lotes.view','lotes.create','lotes.update','lotes.delete'])
                @php $lotesOpen = request()->routeIs('lotes.*','actividades.*','certificaciones.*'); @endphp
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $lotesOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-lotes">
                        <i class="ag-nav-icon fas fa-map-marked-alt"></i>
                        <span class="ag-nav-text">Lotes y actividades</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $lotesOpen ? 'open' : '' }}" id="sub-lotes">
                        @can('lotes.view')
                        <li class="ag-sub-li"><a href="{{ route('lotes.index') }}" class="ag-sub-a {{ request()->routeIs('lotes.index', 'lotes.show', 'lotes.edit', 'lotes.create', 'lotes.trazabilidad', 'lotes.ubicacion') ? 'active' : '' }}">Lotes</a></li>
                        <li class="ag-sub-li"><a href="{{ route('lotes.mapa') }}" class="ag-sub-a {{ request()->routeIs('lotes.mapa') ? 'active' : '' }}">Mapa de lotes</a></li>
                        @endcan
                        <li class="ag-sub-li"><a href="{{ route('actividades.index') }}" class="ag-sub-a {{ request()->routeIs('actividades.index', 'actividades.show', 'actividades.edit', 'actividades.create') ? 'active' : '' }}">Actividades</a></li>
                        <li class="ag-sub-li"><a href="{{ route('actividades.calendario') }}" class="ag-sub-a {{ request()->routeIs('actividades.calendario') ? 'active' : '' }}">Calendario</a></li>
                        @can('certificaciones.view')
                        <li class="ag-sub-li"><a href="{{ route('certificaciones.index') }}" class="ag-sub-a {{ request()->routeIs('certificaciones.*') ? 'active' : '' }}">Certificaciones</a></li>
                        @endcan
                    </ul>
                </li>
                @endcanany

                {{-- Producción agrícola (cosechas y clima) --}}
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $prodAgrOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-prod-agr">
                        <i class="ag-nav-icon fas fa-seedling"></i>
                        <span class="ag-nav-text">Producción</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $prodAgrOpen ? 'open' : '' }}" id="sub-prod-agr">
                        @unless(auth()->user()?->hasRole('transportista'))
                        <li class="ag-sub-li"><a href="{{ route('producciones.index') }}" class="ag-sub-a {{ request()->routeIs('producciones.*') ? 'active' : '' }}">Cosechas</a></li>
                        @endunless
                        <li class="ag-sub-li"><a href="{{ route('climas.index') }}" class="ag-sub-a {{ request()->routeIs('climas.*') ? 'active' : '' }}">Clima</a></li>
                    </ul>
                </li>

                {{-- Inventario --}}
                @canany(['inventario.view','inventario.create','inventario.update','inventario.delete'])
                @php $invOpen = request()->routeIs('insumos.*'); @endphp
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $invOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-inv">
                        <i class="ag-nav-icon fas fa-boxes"></i>
                        <span class="ag-nav-text">Inventario</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $invOpen ? 'open' : '' }}" id="sub-inv">
                        <li class="ag-sub-li"><a href="{{ route('insumos.index') }}" class="ag-sub-a {{ request()->routeIs('insumos.*') ? 'active' : '' }}">Insumos</a></li>
                    </ul>
                </li>
                @endcanany

                @if($puedeAlmacenAgricola)
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $almAgrOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-alm-agr">
                        <i class="ag-nav-icon fas fa-warehouse"></i>
                        <span class="ag-nav-text">Almacén agrícola</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $almAgrOpen ? 'open' : '' }}" id="sub-alm-agr">
                        <li class="ag-sub-li"><a href="{{ route('almacen-agricola.index') }}" class="ag-sub-a {{ request()->routeIs('almacen-agricola.index', 'almacen-agricola.show', 'almacen-agricola.create', 'almacen-agricola.edit') ? 'active' : '' }}">Almacenes</a></li>
                        @can('almacen.movimientos.view')
                        <li class="ag-sub-li"><a href="{{ route('almacen-agricola.movimientos.index') }}" class="ag-sub-a {{ request()->routeIs('almacen-agricola.movimientos.*') && !request()->routeIs('almacen-agricola.movimientos.reportes') ? 'active' : '' }}">Movimientos</a></li>
                        @endcan
                        @can('almacen.reportes.view')
                        <li class="ag-sub-li"><a href="{{ route('almacen-agricola.movimientos.reportes') }}" class="ag-sub-a {{ request()->routeIs('almacen-agricola.movimientos.reportes') ? 'active' : '' }}">Reportes</a></li>
                        @endcan
                    </ul>
                </li>
                @endif

                @if($esJefeAgr && ! $isAdmin && ($puedeEnvios || $puedeSubmenuEnviosScoped))
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $envAgrOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-env-agr">
                        <i class="ag-nav-icon fas fa-truck"></i>
                        <span class="ag-nav-text">Envíos</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $envAgrOpen ? 'open' : '' }}" id="sub-env-agr">
                        @include('layouts.partials.submenu-envios-items', ['envListadoActivo' => $envListadoActivo])
                        @include('layouts.partials.submenu-catalogos-logistica', ['catalogoSubId' => 'agr'])
                    </ul>
                </li>
                @endif
                @endif

                @if($showOperLogistica)
                <span class="ag-nav-label">Operación logística</span>

                @can('panel_transportista.view')
                <li class="ag-nav-li"><a href="{{ route('dashboard.panel-transportista') }}" class="ag-nav-a {{ request()->routeIs('dashboard.panel-transportista') ? 'active' : '' }}"><i class="ag-nav-icon fas fa-truck-moving"></i><span class="ag-nav-text">Panel Transportista</span></a></li>
                @endcan

                {{-- Envíos --}}
                @if($puedeEnvios)
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $envOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-env">
                        <i class="ag-nav-icon fas fa-truck"></i>
                        <span class="ag-nav-text">Envíos</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $envOpen ? 'open' : '' }}" id="sub-env">
                        @include('layouts.partials.submenu-envios-items', ['envListadoActivo' => $envListadoActivo])
                        {{-- Rutas multientrega ocultas: el flujo operativo es almacén agrícola → planta (un solo trayecto). --}}
                        @unless(auth()->user()?->hasRole('transportista'))
                        @if($isAdmin || auth()->user()?->can('transportistas.view'))
                        <li class="ag-sub-li"><a href="{{ route('envios.transportistas') }}" class="ag-sub-a {{ request()->routeIs('envios.transportistas*') ? 'active' : '' }}">Transportistas</a></li>
                        @endif
                        @if($isAdmin || auth()->user()?->can('vehiculos.view'))
                        <li class="ag-sub-li"><a href="{{ route('envios.vehiculos') }}" class="ag-sub-a {{ request()->routeIs('envios.vehiculos*') ? 'active' : '' }}">Vehículos</a></li>
                        @endif
                        @include('layouts.partials.submenu-catalogos-logistica', ['catalogoSubId' => 'admin'])
                        @endunless
                        @if($puedeReportesLogistica)
                        <li class="ag-sub-li">
                            <a href="#" class="ag-sub-a {{ $logMasOpen ? 'group-open' : '' }}" data-toggle-sub="sub-log-mas">
                                Reportes
                                <i class="fas fa-chevron-right ag-sub-arrow"></i>
                            </a>
                            <ul class="ag-subnav ag-subnav-nested {{ $logMasOpen ? 'open' : '' }}" id="sub-log-mas">
                                @if(auth()->user()?->can('envios.view') && auth()->user()?->can('reportes.view'))
                                <li class="ag-sub-li"><a href="{{ route('envios.reportes-distribucion') }}" class="ag-sub-a {{ request()->routeIs('envios.reportes-distribucion') ? 'active' : '' }}">Reportes distribución</a></li>
                                @endif
                            </ul>
                        </li>
                        @endif
                    </ul>
                </li>
                @endif
                @endif

                @if($showProdPlantaSection)
                <span class="ag-nav-label">Producción planta</span>

                @can('panel_planta.view')
                @if(! ($authUser && \App\Support\UsuarioRol::esOperarioPlanta($authUser)))
                <li class="ag-nav-li"><a href="{{ route('dashboard.panel-planta') }}" class="ag-nav-a {{ request()->routeIs('dashboard.panel-planta') ? 'active' : '' }}"><i class="ag-nav-icon fas fa-industry"></i><span class="ag-nav-text">Panel Planta</span></a></li>
                @endif
                @endcan

                @if($puedeProdPlanta)
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $prodPlaMenuOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-prod-pla">
                        <i class="ag-nav-icon fas fa-cogs"></i>
                        <span class="ag-nav-text">Producción</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $prodPlaMenuOpen ? 'open' : '' }}" id="sub-prod-pla">
                        @can('lote_produccion.view')
                        <li class="ag-sub-li"><a href="{{ route('procesamiento.index') }}" class="ag-sub-a {{ request()->routeIs('procesamiento.*') && ! request()->routeIs('certificaciones-planta.*') ? 'active' : '' }}">Procesamiento de Lote</a></li>
                        @if($isAdmin || \App\Support\UsuarioRol::gestionaPlanta($authUser))
                        <li class="ag-sub-li"><a href="{{ route('certificaciones-planta.index') }}" class="ag-sub-a {{ request()->routeIs('certificaciones-planta.*') ? 'active' : '' }}">Certificaciones</a></li>
                        @endif
                        @endcan
                        @if($authUser && \App\Support\UsuarioRol::esOperarioPlanta($authUser))
                        <li class="ag-sub-li"><a href="{{ route('tareas-planta.index') }}" class="ag-sub-a {{ request()->routeIs('tareas-planta.*') ? 'active' : '' }}">Mis tareas de transformación</a></li>
                        @endif
                        @if($isAdmin || \App\Support\UsuarioRol::gestionaPlanta($authUser))
                        <li class="ag-sub-li"><a href="{{ route('procesos-planta.index') }}" class="ag-sub-a {{ request()->routeIs('procesos-planta.*') ? 'active' : '' }}">Procesos de planta</a></li>
                        <li class="ag-sub-li"><a href="{{ route('plantillas-transformacion.index') }}" class="ag-sub-a {{ request()->routeIs('plantillas-transformacion.*') ? 'active' : '' }}">Procesos de transformación</a></li>
                        <li class="ag-sub-li"><a href="{{ route('maquinas-planta.index') }}" class="ag-sub-a {{ request()->routeIs('maquinas-planta.*') ? 'active' : '' }}">Máquinas de planta</a></li>
                        <li class="ag-sub-li"><a href="{{ route('variables-estandar.index') }}" class="ag-sub-a {{ request()->routeIs('variables-estandar.*') ? 'active' : '' }}">Variables estándar</a></li>
                        <li class="ag-sub-li"><a href="{{ route('produccion-planta.catalogos.index', 'tipos-empaque') }}" class="ag-sub-a {{ request()->routeIs('produccion-planta.catalogos.*') ? 'active' : '' }}">Tipos de empaque</a></li>
                        @endif
                    </ul>
                </li>
                @endif

                @if($puedeAlmacenPlanta)
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $almPlaOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-alm-pla">
                        <i class="ag-nav-icon fas fa-dolly"></i>
                        <span class="ag-nav-text">Almacén de planta</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $almPlaOpen ? 'open' : '' }}" id="sub-alm-pla">
                        <li class="ag-sub-li"><a href="{{ route('almacen-planta.index') }}" class="ag-sub-a {{ request()->routeIs('almacen-planta.index', 'almacen-planta.show', 'almacen-planta.create', 'almacen-planta.edit', 'almacen-planta.inventario.*') ? 'active' : '' }}">Almacenes</a></li>
                        @can('almacen.movimientos.view')
                        <li class="ag-sub-li"><a href="{{ route('almacen-planta.movimientos.index') }}" class="ag-sub-a {{ request()->routeIs('almacen-planta.movimientos.*') && !request()->routeIs('almacen-planta.movimientos.reportes') ? 'active' : '' }}">Movimientos</a></li>
                        @endcan
                        @can('almacen.reportes.view')
                        <li class="ag-sub-li"><a href="{{ route('almacen-planta.movimientos.reportes') }}" class="ag-sub-a {{ request()->routeIs('almacen-planta.movimientos.reportes') ? 'active' : '' }}">Reportes</a></li>
                        @endcan
                    </ul>
                </li>
                @endif

                @if($esJefePlantaNav && ! $isAdmin && ($puedeEnvios || $puedeSubmenuEnviosScoped))
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $envPlantaOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-env-planta">
                        <i class="ag-nav-icon fas fa-truck"></i>
                        <span class="ag-nav-text">Envíos</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $envPlantaOpen ? 'open' : '' }}" id="sub-env-planta">
                        @include('layouts.partials.submenu-envios-items', ['envListadoActivo' => $envListadoActivo])
                        @include('layouts.partials.submenu-catalogos-logistica', ['catalogoSubId' => 'planta'])
                    </ul>
                </li>
                @endif
                @endif

                @php
                    $puedePedidosDistMenuPdv = $isAdmin || $esMinoristaOperativo;
                    $puedePuntoVentaMenu = $isAdmin || $esMinoristaOperativo
                        || ($authUser && $authUser->can('punto_venta.view') && ! $esMayoristaOperativo);
                    $pvMenuOpen = request()->routeIs('punto-venta.puntos.*', 'punto-venta.inventario.*')
                        || ($pedidosEnSeccionPdv ?? false);
                @endphp

                @if($puedeMenuMayorista)
                <span class="ag-nav-label">Mayorista</span>

                @if($esMayoristaOperativo || $isAdmin)
                <li class="ag-nav-li">
                    <a href="{{ route('dashboard.panel-mayorista') }}" class="ag-nav-a {{ request()->routeIs('dashboard.panel-mayorista') ? 'active' : '' }}">
                        <i class="ag-nav-icon fas fa-warehouse"></i>
                        <span class="ag-nav-text">Panel Mayorista</span>
                    </a>
                </li>
                @endif

                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $mayMenuOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-mayorista">
                        <i class="ag-nav-icon fas fa-boxes"></i>
                        <span class="ag-nav-text">Operación mayorista</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $mayMenuOpen ? 'open' : '' }}" id="sub-mayorista">
                        <li class="ag-sub-li">
                            <a href="{{ route('almacen-mayorista.index') }}" class="ag-sub-a {{ request()->routeIs('almacen-mayorista.index', 'almacen-mayorista.show', 'almacen-mayorista.create', 'almacen-mayorista.edit', 'almacen-mayorista.inventario.*') ? 'active' : '' }}">Almacenes</a>
                        </li>
                        @can('inventario.view')
                        <li class="ag-sub-li">
                            <a href="{{ route('almacen-mayorista.traslados-planta.index') }}" class="ag-sub-a {{ request()->routeIs('almacen-mayorista.traslados-planta.*') ? 'active' : '' }}">Recepciones de planta</a>
                        </li>
                        @endcan
                        @can('almacen.movimientos.view')
                        <li class="ag-sub-li">
                            <a href="{{ route('almacen-mayorista.movimientos.index') }}" class="ag-sub-a {{ request()->routeIs('almacen-mayorista.movimientos.*') && !request()->routeIs('almacen-mayorista.movimientos.reportes') ? 'active' : '' }}">Movimientos</a>
                        </li>
                        @endcan
                        @can('almacen.reportes.view')
                        <li class="ag-sub-li">
                            <a href="{{ route('almacen-mayorista.movimientos.reportes') }}" class="ag-sub-a {{ request()->routeIs('almacen-mayorista.movimientos.reportes') ? 'active' : '' }}">Reportes</a>
                        </li>
                        @endcan
                        @can('pedidos_distribucion.view')
                        <li class="ag-sub-li">
                            <a href="{{ route('punto-venta.pedidos.index', ['ctx' => 'mayorista']) }}" class="ag-sub-a {{ ($pedidosEnSeccionMayorista ?? false) ? 'active' : '' }}">Pedidos minoristas</a>
                        </li>
                        @endcan
                    </ul>
                </li>

                @if($esMayoristaOperativo && ! $isAdmin && ($puedeEnvios || $puedeSubmenuEnviosScoped))
                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $envMayOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-env-may">
                        <i class="ag-nav-icon fas fa-truck"></i>
                        <span class="ag-nav-text">Envíos</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $envMayOpen ? 'open' : '' }}" id="sub-env-may">
                        @include('layouts.partials.submenu-envios-items', ['envListadoActivo' => $envListadoActivo])
                        @include('layouts.partials.submenu-catalogos-logistica', ['catalogoSubId' => 'may'])
                    </ul>
                </li>
                @endif
                @endif

                @if($puedePuntoVentaMenu || $puedePedidosDistMenuPdv)
                <span class="ag-nav-label">Punto de venta</span>

                @if($esMinoristaOperativo || $isAdmin)
                <li class="ag-nav-li">
                    <a href="{{ route('dashboard.panel-minorista') }}" class="ag-nav-a {{ request()->routeIs('dashboard.panel-minorista') ? 'active' : '' }}">
                        <i class="ag-nav-icon fas fa-shopping-basket"></i>
                        <span class="ag-nav-text">Panel Minorista</span>
                    </a>
                </li>
                @endif

                <li class="ag-nav-li">
                    <a href="#" class="ag-nav-a {{ $pvMenuOpen ? 'active group-open' : '' }}" data-toggle-sub="sub-pv">
                        <i class="ag-nav-icon fas fa-store"></i>
                        <span class="ag-nav-text">Comercialización</span>
                        <i class="ag-nav-arrow fas fa-chevron-right"></i>
                    </a>
                    <ul class="ag-subnav {{ $pvMenuOpen ? 'open' : '' }}" id="sub-pv">
                        @if($puedePuntoVentaMenu)
                        <li class="ag-sub-li">
                            <a href="{{ route('punto-venta.puntos.index') }}" class="ag-sub-a {{ request()->routeIs('punto-venta.puntos.*') && !request()->routeIs('punto-venta.inventario.*') ? 'active' : '' }}">Puntos de venta</a>
                        </li>
                        <li class="ag-sub-li">
                            <a href="{{ route('punto-venta.inventario.index') }}" class="ag-sub-a {{ request()->routeIs('punto-venta.inventario.*') ? 'active' : '' }}">Inventario</a>
                        </li>
                        @endif
                        @if($puedePedidosDistMenuPdv)
                        <li class="ag-sub-li">
                            <a href="{{ route('punto-venta.pedidos.index', ['ctx' => 'pdv']) }}" class="ag-sub-a {{ ($pedidosEnSeccionPdv ?? false) ? 'active' : '' }}">Pedidos de distribución</a>
                        </li>
                        @endif
                        {{-- Planificar distribución: deshabilitado temporalmente --}}
                        @if(false && $isAdmin && \App\Support\UsuarioRol::puedePlanificarDistribucion($authUser))
                        <li class="ag-sub-li">
                            <a href="{{ route('punto-venta.rutas.index') }}" class="ag-sub-a {{ request()->routeIs('punto-venta.rutas.*') ? 'active' : '' }}">Planificar distribución</a>
                        </li>
                        @endif
                    </ul>
                </li>
                @endif
                @endif {{-- /TEMPORAL ! $isAdmin --}}

                @if(\App\Support\UsuarioRol::puedeGestionarUsuarios($authUser) || \App\Support\ReporteCatalogo::usuarioTieneAcceso(auth()->user()))
                <span class="ag-nav-label">{{ ($esJefeAgr || ($authUser && $authUser->hasRole('jefe_planta'))) && ! $isAdmin ? 'Equipo' : 'Administración' }}</span>

                @if($isAdmin && $pendientesSolicitudes > 0)
                <li class="ag-nav-li">
                    <a href="{{ route('gestion.index', ['estado' => 'pendiente']) }}" class="ag-nav-a {{ request('estado') === 'pendiente' ? 'active' : '' }}">
                        <i class="ag-nav-icon fas fa-user-clock"></i>
                        <span class="ag-nav-text">Solicitudes pendientes</span>
                        <span class="badge badge-warning ml-auto">{{ $pendientesSolicitudes }}</span>
                    </a>
                </li>
                @endif

                @if(\App\Support\UsuarioRol::puedeGestionarUsuarios($authUser))
                <li class="ag-nav-li">
                    <a href="{{ route('gestion.index') }}" class="ag-nav-a {{ request()->routeIs('gestion.*') ? 'active' : '' }}">
                        <i class="ag-nav-icon fas fa-users-cog"></i>
                        <span class="ag-nav-text">Gestión de usuarios</span>
                    </a>
                </li>
                @endif

                @if(\App\Support\ReporteCatalogo::usuarioTieneAcceso(auth()->user()))
                <li class="ag-nav-li">
                    <a href="{{ route('reportes.index') }}" class="ag-nav-a {{ request()->routeIs('reportes.*') ? 'active' : '' }}">
                        <i class="ag-nav-icon fas fa-chart-bar"></i>
                        <span class="ag-nav-text">Centro de reportes</span>
                    </a>
                </li>
                @endif
                @endif

            </ul>
        </nav>

        {{-- Footer --}}
        <div class="ag-sb-footer">
            <a href="{{ route('logout') }}" class="ag-sb-foot-btn ag-sb-foot-btn--link">
                <i class="fas fa-sign-out-alt" style="width:16px;text-align:center;"></i>
                <span>Cerrar sesión</span>
            </a>
        </div>

    </aside>