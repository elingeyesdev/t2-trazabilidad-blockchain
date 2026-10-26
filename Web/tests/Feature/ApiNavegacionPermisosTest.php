<?php

namespace Tests\Feature;

use App\Models\Usuario;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ApiNavegacionPermisosTest extends TestCase
{
    use RefreshDatabase;

    private function usuario(): Usuario
    {
        return Usuario::create([
            'nombre' => 'Navegacion',
            'apellido' => 'Prueba',
            'email' => 'navegacion@example.test',
            'nombreusuario' => 'navegacion',
            'passwordhash' => Hash::make('clave-de-prueba'),
            'activo' => true,
            'estado_cuenta' => 'aprobado',
        ]);
    }

    public function test_peticiones_manuales_sin_permisos_no_eluden_el_menu(): void
    {
        $usuario = $this->usuario();
        $headers = ['Authorization' => 'Bearer '.$usuario->createToken('navegacion')->plainTextToken];

        foreach (['lotes', 'actividades', 'producciones', 'almacenes', 'insumos',
            'almacen-movimientos', 'certificaciones', 'pedidos', 'incidentes',
            'rutas-multi', 'asignaciones-multiples', 'documentos-entrega', 'usuarios'] as $endpoint) {
            $this->getJson('/api/'.$endpoint, $headers)->assertForbidden();
        }

        $this->getJson('/api/me', $headers)->assertOk()->assertJsonPath('permissions', []);
    }

    public function test_nombre_de_rol_admin_no_concede_bypass(): void
    {
        $usuario = $this->usuario();
        $usuario->assignRole(Role::findOrCreate('admin', 'web'));
        $this->actingAs($usuario, 'sanctum');

        $this->getJson('/api/pedidos')->assertForbidden();
        $this->getJson('/api/usuarios')->assertForbidden();
    }

    public function test_permiso_directo_autoriza_consulta_sin_asignar_roles(): void
    {
        $usuario = $this->usuario();
        $usuario->givePermissionTo(Permission::findOrCreate('pedidos.view', 'web'));
        $this->actingAs($usuario, 'sanctum');

        $this->getJson('/api/me')->assertOk()->assertJsonPath('permissions', ['pedidos.view']);
        $this->getJson('/api/pedidos')->assertOk()->assertExactJson([]);
        $this->getJson('/api/usuarios')->assertForbidden();
    }

    public function test_consultar_usuarios_requiere_admin_y_no_solo_view(): void
    {
        $usuario = $this->usuario();
        $usuario->givePermissionTo(Permission::findOrCreate('usuarios.view', 'web'));
        $this->actingAs($usuario, 'sanctum');
        $this->getJson('/api/usuarios')->assertForbidden();

        $usuario->givePermissionTo(Permission::findOrCreate('usuarios.admin', 'web'));
        $this->getJson('/api/usuarios')->assertOk()->assertJsonPath('0.usuarioid', $usuario->usuarioid);
    }
}
