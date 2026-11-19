        <header class="ag-topbar">
            <button type="button" class="ag-tb-icon-btn" id="agToggle" title="Mostrar u ocultar menú" aria-label="Mostrar u ocultar menú" aria-controls="agSidebar" aria-expanded="true">
                <i class="fas fa-bars"></i>
            </button>

            <div class="ag-tb-breadcrumb">
                <span class="ag-tb-title">@yield('page_title', trim($__env->yieldContent('title', 'AgroFusion')))</span>
                @hasSection('breadcrumbs')
                    <span style="color:var(--border-2);margin:0 4px;">/</span>
                    <nav aria-label="breadcrumb">
                        <ol class="breadcrumb">
                            @yield('breadcrumbs')
                        </ol>
                    </nav>
                @endif
            </div>

            <div class="ag-tb-right">
                {{-- Fullscreen --}}
                <button class="ag-tb-icon-btn" id="agFullscreen" title="Pantalla completa">
                    <i class="fas fa-expand"></i>
                </button>

                {{-- User menu --}}
                <div class="ag-user-wrap">
                    <button type="button" class="ag-user-btn" id="agUserBtn" aria-label="Menú de usuario" aria-controls="agUserDropdown" aria-expanded="false">
                        <img src="{{ $userImg }}" alt="Avatar"
                             data-avatar-fallback="{{ $userImgFallback }}"
                             onerror="if(this.dataset.avatarFallback){this.onerror=null;this.src=this.dataset.avatarFallback;}">
                        <span class="ag-user-btn-name">{{ $userFull }}</span>
                        <i class="fas fa-chevron-down"></i>
                    </button>

                    <div class="ag-dropdown" id="agUserDropdown">
                        <div class="ag-dd-header">
                            <span class="ag-dd-user-name">{{ $userFull }}</span>
                            <span class="ag-dd-user-role">
                                <span class="role-badge {{ $roleCss }}">{{ ucfirst($userRole) }}</span>
                            </span>
                        </div>
                        <div class="ag-dd-body">
                            <a href="{{ route('profile.show') }}" class="ag-dd-item">
                                <i class="fas fa-user-circle" style="width:14px;"></i> Mi perfil
                            </a>
                            <div class="ag-dd-sep"></div>
                            <a href="{{ route('logout') }}" class="ag-dd-item danger">
                                <i class="fas fa-sign-out-alt" style="width:14px;"></i> Cerrar sesión
                            </a>
                        </div>
                    </div>
                </div>
            </div>
        </header>
