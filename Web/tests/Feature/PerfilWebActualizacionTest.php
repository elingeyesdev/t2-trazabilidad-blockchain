<?php

namespace Tests\Feature;

use App\Models\Usuario;
use App\Support\CuentaEstado;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class PerfilWebActualizacionTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
    }

    private function crearUsuario(bool $nombreEditado = false): Usuario
    {
        $usuario = Usuario::create([
            'nombre' => 'Ana',
            'apellido' => 'Mamani',
            'email' => 'perfil-web@example.test',
            'nombreusuario' => 'ana',
            'passwordhash' => Hash::make('clave-de-prueba'),
            'activo' => true,
            'estado_cuenta' => CuentaEstado::APROBADO,
            'bienvenida_vista' => true,
            'nombreusuario_editado' => $nombreEditado,
        ]);
        $usuario->assignRole(Role::findOrCreate('agricultor', 'web'));

        return $usuario;
    }

    public function test_web_conserva_redireccion_y_actualiza_nombre_y_foto(): void
    {
        $usuario = $this->crearUsuario();
        $this->actingAs($usuario)->put(route('profile.update'), [
            'nombreusuario' => 'ana.mamani',
            'imagen' => UploadedFile::fake()->image('foto.png'),
        ])
            ->assertRedirect(route('profile.show'))
            ->assertSessionHas('success', 'Perfil actualizado correctamente.');

        $usuario->refresh();
        $this->assertSame('ana.mamani', $usuario->nombreusuario);
        $this->assertTrue($usuario->nombreusuario_editado);
        Storage::disk('public')->assertExists(substr($usuario->imagenurl, strlen('/storage/')));
    }

    public function test_web_sigue_permitiendo_foto_e_ignora_nombre_ya_bloqueado(): void
    {
        $usuario = $this->crearUsuario(nombreEditado: true);
        $this->actingAs($usuario)->put(route('profile.update'), [
            'nombreusuario' => 'segundo-intento',
            'imagen' => UploadedFile::fake()->image('foto.png'),
        ])->assertRedirect(route('profile.show'));

        $usuario->refresh();
        $this->assertSame('ana', $usuario->nombreusuario);
        Storage::disk('public')->assertExists(substr($usuario->imagenurl, strlen('/storage/')));
    }

    public function test_web_conserva_validacion_de_foto_y_nombre_obligatorio(): void
    {
        $usuario = $this->crearUsuario();
        $this->actingAs($usuario)->from(route('profile.show'))->put(route('profile.update'), [
            'imagen' => UploadedFile::fake()->image('foto.jpg')->size(2049),
        ])
            ->assertRedirect(route('profile.show'))
            ->assertSessionHasErrors(['nombreusuario', 'imagen']);

        $this->assertNull($usuario->fresh()->imagenurl);
        $this->assertFalse($usuario->fresh()->nombreusuario_editado);
    }
}
