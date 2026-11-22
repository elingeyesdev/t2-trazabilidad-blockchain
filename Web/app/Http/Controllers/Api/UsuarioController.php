<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Usuario;
use App\Services\UsuarioEliminacionService;
use App\Services\UsuarioUsernameService;
use App\Support\CuentaEstado;
use App\Support\PermissionMatrixSync;
use App\Support\TransportistaFlotaCatalogo;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Spatie\Permission\Models\Role;

class UsuarioController extends Controller
{
    public function index()
    {
        return response()->json(
            Usuario::with('roles')->get()
        );
    }

    public function show($id)
    {
        return response()->json(
            Usuario::with('roles')->findOrFail($id)
        );
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'nombre' => 'required|string|max:100',
            'apellido' => 'required|string|max:100',
            'email' => 'required|email|max:100|unique:usuario,email',
            'nombreusuario' => 'required|string|max:100|unique:usuario,nombreusuario',
            'telefono' => 'nullable|string|max:20',
            'password' => 'required|string|min:6',
            'imagenurl' => 'nullable|string|max:250',
            'informacionadicional' => 'nullable|string',
            'activo' => 'boolean',
        ]);

        $usuario = Usuario::create([
            ...$data,
            'passwordhash' => Hash::make($data['password']),
        ]);

        return response()->json($usuario, 201);
    }

    public function update(Request $request, $id)
    {
        $usuario = Usuario::findOrFail($id);

        $data = $request->validate([
            'nombre' => 'sometimes|string|max:100',
            'apellido' => 'sometimes|string|max:100',
            'email' => 'sometimes|email|max:100|unique:usuario,email,' . $id . ',usuarioid',
            'nombreusuario' => 'sometimes|string|max:100|unique:usuario,nombreusuario,' . $id . ',usuarioid',
            'telefono' => 'nullable|string|max:20',
            'password' => 'nullable|string|min:6',
            'imagenurl' => 'nullable|string|max:250',
            'informacionadicional' => 'nullable|string',
            'activo' => 'boolean',
        ]);

        if (isset($data['password'])) {
            $data['passwordhash'] = Hash::make($data['password']);
            unset($data['password']);
        }

        $usuario->update($data);

        return response()->json($usuario);
    }

    public function destroy($id)
    {
        $usuario = Usuario::findOrFail($id);
        $usuario->delete();

        return response()->json(['message' => 'Eliminado correctamente']);
    }

    public function aprobar(Request $request, $id)
    {
        $usuario = Usuario::with('roles')->findOrFail($id);
        if (! CuentaEstado::esPendiente($usuario->estado_cuenta)) {
            return response()->json([
                'message' => 'Esta cuenta ya fue aprobada anteriormente.',
                'user' => $usuario,
            ]);
        }

        $rolNombre = $usuario->rol_solicitado ?: $usuario->role ?: 'agricultor';
        $rolesPermitidos = array_merge(CuentaEstado::rolesRegistroPublico(), ['agricultor']);
        if (! in_array($rolNombre, $rolesPermitidos, true)) {
            return response()->json([
                'message' => 'La solicitud no tiene un rol válido para aprobar.',
            ], 422);
        }

        if ($rolNombre === 'transportista') {
            $request->validate([
                'ambito_flota' => ['required', 'in:'.implode(',', TransportistaFlotaCatalogo::valores())],
            ]);
        }

        Role::firstOrCreate(['name' => $rolNombre, 'guard_name' => 'web']);
        PermissionMatrixSync::syncRole($rolNombre);

        $nombreusuario = trim((string) ($usuario->nombreusuario ?? ''));
        if ($nombreusuario === '') {
            $nombreusuario = app(UsuarioUsernameService::class)->generarDesdeNombreApellido(
                (string) $usuario->nombre,
                (string) $usuario->apellido
            );
        }

        $usuario->update([
            'estado_cuenta' => CuentaEstado::APROBADO,
            'activo' => true,
            'role' => $rolNombre,
            'nombreusuario' => $nombreusuario,
            'motivo_rechazo' => null,
            'revisado_por' => $request->user()?->getKey(),
            'fecha_revision' => now(),
            'fechamodificacion' => now(),
        ]);
        $usuario->syncRoles([$rolNombre]);

        return response()->json([
            'message' => 'Solicitud aprobada correctamente.',
            'user' => $usuario->fresh('roles'),
        ]);
    }

    public function rechazar($id)
    {
        $usuario = Usuario::findOrFail($id);
        if (! CuentaEstado::esPendiente($usuario->estado_cuenta)) {
            return response()->json([
                'message' => 'Solo se pueden rechazar solicitudes pendientes.',
            ], 409);
        }

        app(UsuarioEliminacionService::class)->eliminar($usuario);

        return response()->json([
            'message' => 'Solicitud rechazada y eliminada del sistema.',
        ]);
    }
}