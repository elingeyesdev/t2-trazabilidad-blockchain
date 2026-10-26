<?php

namespace Tests\Feature;

use App\Models\Usuario;
use App\Support\CuentaEstado;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ApiPerfilConsultaTest extends TestCase
{
    use RefreshDatabase;

    private function crearUsuario(string $identificador = 'perfil', array $atributos = []): Usuario
    {
        return Usuario::create([
            'nombre' => 'Ana',
            'apellido' => 'Mamani',
            'email' => $identificador.'@example.test',
            'nombreusuario' => $identificador,
            'passwordhash' => Hash::make('clave-de-prueba'),
            'activo' => true,
            'estado_cuenta' => CuentaEstado::APROBADO,
            'nombreusuario_editado' => false,
            ...$atributos,
        ]);
    }

    private function bearer(Usuario $usuario): array
    {
        return ['Authorization' => 'Bearer '.$usuario->createToken('perfil-test')->plainTextToken];
    }

    public function test_consulta_requiere_autenticacion(): void
    {
        $this->getJson('/api/me')->assertUnauthorized();
    }

    public function test_token_invalido_no_permite_consultar_el_perfil(): void
    {
        $this->getJson('/api/me', ['Authorization' => 'Bearer token-invalido'])
            ->assertUnauthorized();
    }

    public function test_token_revocado_no_permite_consultar_el_perfil(): void
    {
        $usuario = $this->crearUsuario();
        $token = $usuario->createToken('revocado');
        $token->accessToken->delete();

        $this->getJson('/api/me', ['Authorization' => 'Bearer '.$token->plainTextToken])
            ->assertUnauthorized();
    }

    public function test_token_vencido_no_permite_consultar_el_perfil(): void
    {
        $usuario = $this->crearUsuario();
        $token = $usuario->createToken('vencido', ['*'], now()->subMinute());

        $this->getJson('/api/me', ['Authorization' => 'Bearer '.$token->plainTextToken])
            ->assertUnauthorized();
    }

    public function test_migracion_conserva_tokens_si_la_tabla_ya_existe(): void
    {
        $usuario = $this->crearUsuario();
        $headers = $this->bearer($usuario);
        $migracion = require database_path('migrations/2026_10_25_000000_create_personal_access_tokens_table.php');

        $migracion->up();

        $this->getJson('/api/me', $headers)
            ->assertOk()
            ->assertJsonPath('usuarioid', $usuario->usuarioid);
    }

    public function test_devuelve_perfil_y_union_de_permisos_directos_y_de_roles(): void
    {
        foreach (['lotes.view', 'inventario.view', 'usuarios.view'] as $nombre) {
            Permission::findOrCreate($nombre, 'web');
        }
        $agricultor = Role::findOrCreate('agricultor', 'web');
        $agricultor->givePermissionTo('lotes.view');
        $operador = Role::findOrCreate('operador', 'web');
        $operador->givePermissionTo(['lotes.view', 'inventario.view']);

        $usuario = $this->crearUsuario(atributos: [
            'telefono' => '70000000',
            'ci_nit' => '123456',
            'informacionadicional' => 'Información interna no necesaria para Flutter',
            'carta_motivacion' => 'Contenido de la solicitud',
        ]);
        $usuario->assignRole($agricultor, $operador);
        $usuario->givePermissionTo(['lotes.view', 'usuarios.view']);

        $this->getJson('/api/me', $this->bearer($usuario))
            ->assertOk()
            ->assertJsonPath('usuarioid', $usuario->usuarioid)
            ->assertJsonPath('nombre', 'Ana')
            ->assertJsonPath('apellido', 'Mamani')
            ->assertJsonPath('email', 'perfil@example.test')
            ->assertJsonPath('nombreusuario', 'perfil')
            ->assertJsonPath('telefono', '70000000')
            ->assertJsonPath('ci_nit', '123456')
            ->assertJsonPath('roles.0.name', 'agricultor')
            ->assertJsonPath('roles.1.name', 'operador')
            ->assertJsonPath('permissions', ['inventario.view', 'lotes.view', 'usuarios.view'])
            ->assertJsonPath('nombreusuario_editado', false)
            ->assertJsonPath('profile_capabilities.update_username', true)
            ->assertJsonPath('profile_capabilities.update_photo', true)
            ->assertJsonMissingPath('data')
            ->assertJsonMissingPath('user')
            ->assertJsonMissingPath('passwordhash')
            ->assertJsonMissingPath('token')
            ->assertJsonMissingPath('tokens')
            ->assertJsonMissingPath('informacionadicional')
            ->assertJsonMissingPath('carta_motivacion')
            ->assertJsonMissingPath('roles.0.pivot')
            ->assertJsonMissingPath('roles.0.permissions');
    }

    public function test_usuario_sin_roles_puede_consultar_su_perfil_con_listas_vacias(): void
    {
        $usuario = $this->crearUsuario();

        $this->getJson('/api/me', $this->bearer($usuario))
            ->assertOk()
            ->assertJsonPath('roles', [])
            ->assertJsonPath('permissions', []);
    }

    public function test_parametros_de_otro_usuario_no_cambian_el_perfil_consultado(): void
    {
        $usuario = $this->crearUsuario('propio');
        $otro = $this->crearUsuario('otro', ['nombre' => 'Otro usuario']);

        $this->getJson('/api/me?usuarioid='.$otro->usuarioid, $this->bearer($usuario))
            ->assertOk()
            ->assertJsonPath('usuarioid', $usuario->usuarioid)
            ->assertJsonPath('email', 'propio@example.test');
    }

    public function test_informa_si_el_cambio_de_nombre_ya_fue_utilizado(): void
    {
        $usuario = $this->crearUsuario(atributos: ['nombreusuario_editado' => true]);

        $this->getJson('/api/me', $this->bearer($usuario))
            ->assertOk()
            ->assertJsonPath('nombreusuario_editado', true)
            ->assertJsonPath('profile_capabilities.update_username', false)
            ->assertJsonPath('profile_capabilities.update_photo', true);
    }

    public function test_cuenta_desactivada_despues_de_emitir_token_recibe_403_json(): void
    {
        $usuario = $this->crearUsuario();
        $headers = $this->bearer($usuario);
        $usuario->update(['activo' => false]);

        $this->getJson('/api/me', $headers)
            ->assertForbidden()
            ->assertExactJson(['message' => 'Tu cuenta no está activa.']);
    }

    public function test_cuenta_pendiente_despues_de_emitir_token_recibe_403_json(): void
    {
        $usuario = $this->crearUsuario();
        $headers = $this->bearer($usuario);
        $usuario->update(['estado_cuenta' => CuentaEstado::PENDIENTE]);

        $this->getJson('/api/me', $headers)
            ->assertForbidden()
            ->assertExactJson(['message' => 'Tu cuenta está pendiente de aprobación por un administrador.']);
    }
}
