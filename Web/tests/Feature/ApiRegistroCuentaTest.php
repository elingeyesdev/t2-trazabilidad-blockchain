<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ApiRegistroCuentaTest extends TestCase
{
    use RefreshDatabase;

    private function solicitud(): array
    {
        return [
            'nombre' => 'Ana',
            'apellido' => 'Mamani',
            'email' => 'registro-flutter@example.test',
            'nombreusuario' => 'ana.mamani',
            'password' => 'clave-de-prueba',
        ];
    }

    public function test_registro_api_exige_el_nombre_de_usuario_que_omitia_react_native(): void
    {
        $datos = $this->solicitud();
        unset($datos['nombreusuario']);

        $this->postJson('/api/register', $datos)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('nombreusuario');
        $this->assertDatabaseMissing('usuario', ['email' => $datos['email']]);
    }

    public function test_registro_api_mantiene_cuenta_pendiente_sin_token_ni_rol_administrativo(): void
    {
        Role::findOrCreate('agricultor', 'web');
        $datos = $this->solicitud();

        $this->postJson('/api/register', [
            ...$datos,
            'role' => 'admin',
            'roles' => ['admin'],
            'rol_deseado' => 'admin',
        ])
            ->assertCreated()
            ->assertJsonPath('user.email', $datos['email'])
            ->assertJsonPath('user.estado_cuenta', 'pendiente')
            ->assertJsonPath('user.role', 'agricultor')
            ->assertJsonPath('user.roles.0.name', 'agricultor')
            ->assertJsonMissingPath('token');

        $this->postJson('/api/login', [
            'email' => $datos['email'],
            'password' => $datos['password'],
        ])
            ->assertForbidden()
            ->assertExactJson(['message' => 'Tu cuenta está pendiente de aprobación por un administrador.']);
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }
}
