<?php

namespace Tests\Feature;

use App\Models\Usuario;
use App\Support\CuentaEstado;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ApiPerfilFlujoTest extends TestCase
{
    use RefreshDatabase;

    private function cabeceras(string $token): array
    {
        // Cada petición representa una solicitud móvil independiente.
        Auth::forgetGuards();

        return [
            'Accept' => 'application/json',
            'Authorization' => 'Bearer '.$token,
        ];
    }

    public function test_login_consulta_edicion_foto_y_revocacion_de_la_sesion(): void
    {
        Storage::fake('public');
        Permission::findOrCreate('lotes.view', 'web');
        $rol = Role::findOrCreate('agricultor', 'web');
        $rol->givePermissionTo('lotes.view');
        $usuario = Usuario::create([
            'nombre' => 'Ana',
            'apellido' => 'Mamani',
            'email' => 'flujo-perfil@example.test',
            'nombreusuario' => 'ana',
            'passwordhash' => Hash::make('clave-flujo-perfil'),
            'activo' => true,
            'estado_cuenta' => CuentaEstado::APROBADO,
            'nombreusuario_editado' => false,
        ]);
        $usuario->assignRole($rol);

        $login = $this->postJson('/api/login', [
            'email' => 'flujo-perfil@example.test',
            'password' => 'clave-flujo-perfil',
        ])
            ->assertOk()
            ->assertJsonPath('user.usuarioid', $usuario->usuarioid)
            ->assertJsonStructure(['user', 'token']);
        $token = $login->json('token');
        $this->assertIsString($token);

        $this->getJson('/api/me', $this->cabeceras($token))
            ->assertOk()
            ->assertJsonPath('nombreusuario', 'ana')
            ->assertJsonPath('permissions', ['lotes.view'])
            ->assertJsonPath('avatar_url', null)
            ->assertJsonPath('profile_capabilities.update_username', true);

        $this->patchJson('/api/me', ['nombreusuario' => 'ana.mamani'], $this->cabeceras($token))
            ->assertOk()
            ->assertJsonPath('nombreusuario', 'ana.mamani')
            ->assertJsonPath('profile_capabilities.update_username', false);

        $foto = $this->post('/api/me', [
            '_method' => 'PATCH',
            'imagen' => UploadedFile::fake()->image('perfil.png'),
        ], $this->cabeceras($token))
            ->assertOk()
            ->assertJsonPath('nombreusuario', 'ana.mamani')
            ->assertJsonPath('profile_capabilities.update_photo', true);
        $imagenurl = $foto->json('imagenurl');
        Storage::disk('public')->assertExists(substr($imagenurl, strlen('/storage/')));

        $this->getJson('/api/me', $this->cabeceras($token))
            ->assertOk()
            ->assertJsonPath('usuarioid', $usuario->usuarioid)
            ->assertJsonPath('nombreusuario', 'ana.mamani')
            ->assertJsonPath('imagenurl', $imagenurl)
            ->assertJsonPath('avatar_url', $foto->json('avatar_url'))
            ->assertJsonPath('permissions', ['lotes.view']);

        $this->postJson('/api/logout', [], $this->cabeceras($token))
            ->assertOk()
            ->assertJsonPath('message', 'Sesión cerrada correctamente');
        $this->assertDatabaseCount('personal_access_tokens', 0);

        $this->getJson('/api/me', $this->cabeceras($token))->assertUnauthorized();
        $this->patchJson('/api/me', ['nombreusuario' => 'intento-revocado'], $this->cabeceras($token))
            ->assertUnauthorized();
        $this->assertSame('ana.mamani', $usuario->fresh()->nombreusuario);
    }
}
