<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Support\CuentaEstado;
use App\Support\UsuarioRol;
use Illuminate\Http\Request;

class SelectorOperativoController extends Controller
{
    public function catalogo(Request $request, string $catalogo)
    {
        $usuario = $request->user();
        $campo = $usuario->can('lotes.view') && (UsuarioRol::gestionaCampo($usuario) || UsuarioRol::debeAcotarPorAsignacion($usuario));
        $asigna = UsuarioRol::gestionaCampo($usuario) && $usuario->can('lotes.create');
        abort_unless($usuario->can('catalogos.view') || ($catalogo === 'unidadesmedida' ? $campo : $asigna), 403);
        [$clase, $campos] = match ($catalogo) {
            'tipoactividades' => [TipoActividad::class, ['tipoactividadid', 'nombre']],
            'prioridades' => [Prioridad::class, ['prioridadid', 'nombre']],
            'unidadesmedida' => [UnidadMedida::class, ['unidadmedidaid', 'nombre', 'abreviatura', 'categoria']],
            default => abort(404),
        };

        return response()->json($clase::orderBy('nombre')->get($campos));
    }

    public function responsablesActividad(Request $request)
    {
        $actor = $request->user();
        abort_unless(UsuarioRol::gestionaCampo($actor) && $actor->can('lotes.view'), 403);
        $ids = UsuarioRol::idsEmpleadosOperativosDeJefeAgricultor($actor);
        $ids[] = (int) $actor->getKey();
        $opciones = Usuario::whereIn('usuarioid', $ids)->where('activo', true)
            ->where(fn ($q) => $q->whereNull('estado_cuenta')->orWhere('estado_cuenta', CuentaEstado::APROBADO))
            ->orderBy('nombre')->get()->filter(fn ($u) => (int) $u->getKey() === (int) $actor->getKey()
                || UsuarioRol::esResponsableActividadPermitido($u))
            ->map(fn ($u) => ['usuarioid' => (int) $u->getKey(), 'nombre' => $u->nombre,
                'apellido' => $u->apellido, 'role' => (int) $u->getKey() === (int) $actor->getKey() ? 'jefe_agricultor' : 'agricultor'])->values();

        return response()->json($opciones);
    }
}
