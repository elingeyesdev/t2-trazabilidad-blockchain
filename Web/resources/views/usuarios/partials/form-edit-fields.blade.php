@php
    $modoJefe = $modoJefe ?? false;
    $rolActualNombre = $usuario->roles->first()?->name ?: $usuario->role;
    $rolDefaultId = old('rolid');
    if ($rolDefaultId === null && $rolActualNombre) {
        $rolDefaultId = $roles->first(
            fn ($r) => strtolower($r->name) === strtolower($rolActualNombre)
        )?->id ?? '';
    }
@endphp

<section class="usu-edit-section">
    <h4 class="usu-edit-section-title">
        <i class="fas fa-id-card"></i> Identidad
    </h4>
    <div class="row">
        <div class="col-md-6">
            <div class="usu-edit-field">
                <label for="nombre">Nombre <span class="text-danger">*</span></label>
                <div class="usu-edit-input-wrap">
                    <i class="fas fa-user"></i>
                    <input type="text" class="form-control @error('nombre') is-invalid @enderror" id="nombre" name="nombre"
                        value="{{ old('nombre', $usuario->nombre) }}" required placeholder="Nombre">
                </div>
                @error('nombre')<span class="usu-edit-error">{{ $message }}</span>@enderror
            </div>
        </div>
        <div class="col-md-6">
            <div class="usu-edit-field">
                <label for="apellido">Apellido <span class="text-danger">*</span></label>
                <div class="usu-edit-input-wrap">
                    <i class="fas fa-user"></i>
                    <input type="text" class="form-control @error('apellido') is-invalid @enderror" id="apellido" name="apellido"
                        value="{{ old('apellido', $usuario->apellido) }}" required placeholder="Apellido">
                </div>
                @error('apellido')<span class="usu-edit-error">{{ $message }}</span>@enderror
            </div>
        </div>
    </div>
</section>

<section class="usu-edit-section {{ $modoJefe ? 'mb-0' : '' }}">
    <h4 class="usu-edit-section-title">
        <i class="fas fa-at"></i> Acceso y contacto
    </h4>
    <div class="row">
        <div class="col-md-6">
            <div class="usu-edit-field">
                <label for="email">Correo electrónico <span class="text-danger">*</span></label>
                <div class="usu-edit-input-wrap">
                    <i class="fas fa-envelope"></i>
                    <input type="email" class="form-control @error('email') is-invalid @enderror" id="email" name="email"
                        value="{{ old('email', $usuario->email) }}" required placeholder="correo@empresa.com">
                </div>
                @error('email')<span class="usu-edit-error">{{ $message }}</span>@enderror
            </div>
        </div>
        <div class="col-md-6">
            <div class="usu-edit-field">
                <label for="nombreusuario">Nombre de usuario @if(! ($usuario->nombreusuario_editado ?? false))<span class="text-danger">*</span>@endif</label>
                <div class="usu-edit-input-wrap">
                    <i class="fas fa-at"></i>
                    @if($modoJefe && ($usuario->nombreusuario_editado ?? false))
                    <input type="text" class="form-control" value="{{ $usuario->nombreusuario }}" readonly disabled>
                    @else
                    <input type="text" class="form-control @error('nombreusuario') is-invalid @enderror" id="nombreusuario" name="nombreusuario"
                        value="{{ old('nombreusuario', $usuario->nombreusuario) }}" required placeholder="usuario">
                    @endif
                </div>
                @error('nombreusuario')<span class="usu-edit-error">{{ $message }}</span>@enderror
            </div>
        </div>
        <div class="col-md-6">
            <div class="usu-edit-field {{ $modoJefe ? '' : 'mb-md-0' }}">
                <label for="telefono">Teléfono</label>
                <div class="usu-edit-input-wrap">
                    <i class="fas fa-phone"></i>
                    <input type="tel" class="form-control js-telefono-bo @error('telefono') is-invalid @enderror" id="telefono" name="telefono"
                        value="{{ old('telefono', $usuario->telefono) }}" placeholder="+591 71234567"
                        inputmode="tel" autocomplete="tel">
                </div>
                @error('telefono')<span class="usu-edit-error">{{ $message }}</span>@enderror
            </div>
        </div>
        @if($modoJefe)
        <div class="col-md-6">
            <div class="usu-edit-field mb-md-0">
                <label for="passwordhash">Nueva contraseña <small class="text-muted">(opcional)</small></label>
                <div class="usu-edit-input-wrap">
                    <i class="fas fa-lock"></i>
                    <input type="password" class="form-control @error('passwordhash') is-invalid @enderror" id="passwordhash" name="passwordhash" minlength="5" autocomplete="new-password">
                </div>
            </div>
        </div>
        @endif
    </div>
</section>

@unless($modoJefe)
@php
    $supervisorActualId = old('supervisor_usuarioid', $usuario->supervisor_usuarioid ?? '');
    $jefesPorRol = $jefesPorRol ?? [];
@endphp
<section class="usu-edit-section mb-0">
    <h4 class="usu-edit-section-title">
        <i class="fas fa-user-shield"></i> Rol y equipo en el sistema
    </h4>
    <div class="row">
        <div class="col-md-6">
            <div class="usu-edit-field mb-0">
                <label for="rolid">Rol asignado</label>
                <div class="usu-edit-input-wrap">
                    <i class="fas fa-shield-alt"></i>
                    <select name="rolid" id="rolid" class="form-control @error('rolid') is-invalid @enderror">
                        <option value="">Sin rol asignado</option>
                        @foreach($roles as $rol)
                            <option value="{{ $rol->id }}" data-role-name="{{ strtolower($rol->name) }}" @selected($rolDefaultId == $rol->id)>
                                {{ \App\Support\UsuarioRol::etiquetaRol($rol->name) }}
                            </option>
                        @endforeach
                    </select>
                </div>
                @error('rolid')<span class="usu-edit-error">{{ $message }}</span>@enderror
            </div>
        </div>
        <div class="col-md-6" id="grupo-supervisor-usuario" style="display: none;">
            <div class="usu-edit-field mb-0">
                <label for="supervisor_usuarioid" id="label-supervisor-usuario">Jefe asignado</label>
                <div class="usu-edit-input-wrap">
                    <i class="fas fa-user-tie"></i>
                    <select name="supervisor_usuarioid" id="supervisor_usuarioid" class="form-control @error('supervisor_usuarioid') is-invalid @enderror">
                        <option value="">Sin jefe asignado</option>
                        @foreach($jefesPorRol as $rolOperario => $jefesLista)
                            @foreach($jefesLista as $jefe)
                                @if((int) $jefe->usuarioid !== (int) $usuario->usuarioid)
                                <option value="{{ $jefe->usuarioid }}" data-operario-role="{{ $rolOperario }}" @selected((string) $supervisorActualId === (string) $jefe->usuarioid)>
                                    {{ $jefe->nombreCompleto() }}{{ $jefe->nombreusuario ? ' (@'.$jefe->nombreusuario.')' : '' }}
                                </option>
                                @endif
                            @endforeach
                        @endforeach
                    </select>
                </div>
                <small class="form-text text-muted d-none" id="aviso-sin-jefes">
                    No hay jefes activos disponibles para este rol.
                </small>
                @error('supervisor_usuarioid')<span class="usu-edit-error">{{ $message }}</span>@enderror
            </div>
        </div>
    </div>
</section>
@push('scripts')
<script>
document.addEventListener('DOMContentLoaded', function () {
    var rolSelect = document.getElementById('rolid');
    var grupo = document.getElementById('grupo-supervisor-usuario');
    var supSelect = document.getElementById('supervisor_usuarioid');
    var label = document.getElementById('label-supervisor-usuario');
    var aviso = document.getElementById('aviso-sin-jefes');
    if (!rolSelect || !grupo || !supSelect) return;

    function actualizarSupervisor() {
        var opt = rolSelect.options[rolSelect.selectedIndex];
        var roleName = opt ? (opt.getAttribute('data-role-name') || '') : '';
        var requiereJefe = roleName === 'agricultor' || roleName === 'planta';

        grupo.style.display = requiereJefe ? '' : 'none';
        if (!requiereJefe) {
            supSelect.value = '';
            return;
        }

        if (label) {
            label.textContent = roleName === 'planta' ? 'Jefe de Planta asignado' : 'Jefe Agricultor asignado';
        }

        var visibles = 0;
        Array.prototype.forEach.call(supSelect.options, function (option) {
            var opRole = option.getAttribute('data-operario-role');
            if (!opRole) return;
            var coincide = opRole === roleName;
            option.hidden = !coincide;
            option.disabled = !coincide;
            if (coincide) visibles++;
        });

        var selectedOpt = supSelect.options[supSelect.selectedIndex];
        if (selectedOpt && selectedOpt.disabled) {
            supSelect.value = '';
        }

        if (aviso) {
            aviso.classList.toggle('d-none', visibles > 0);
        }
    }

    rolSelect.addEventListener('change', actualizarSupervisor);
    actualizarSupervisor();
});
</script>
@endpush
@endunless

@include('partials.telefono-bo-input-script')
