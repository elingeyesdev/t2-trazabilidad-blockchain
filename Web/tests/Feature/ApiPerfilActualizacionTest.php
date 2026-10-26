<?php

namespace Tests\Feature;

use App\Models\Usuario;
use App\Services\PerfilUsuarioService;
use App\Support\CuentaEstado;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Mockery;
use PHPUnit\Framework\Attributes\DataProvider;
use RuntimeException;
use Tests\TestCase;

class ApiPerfilActualizacionTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
    }

    private function crearUsuario(string $nombre = 'perfil', array $atributos = []): Usuario
    {
        return Usuario::create([
            'nombre' => 'Ana',
            'apellido' => 'Mamani',
            'email' => $nombre.'@example.test',
            'nombreusuario' => $nombre,
            'passwordhash' => Hash::make('clave-de-prueba'),
            'activo' => true,
            'estado_cuenta' => CuentaEstado::APROBADO,
            'nombreusuario_editado' => false,
            ...$atributos,
        ]);
    }

    private function bearer(Usuario $usuario): array
    {
        return [
            'Authorization' => 'Bearer '.$usuario->createToken('perfil-test')->plainTextToken,
            'Accept' => 'application/json',
        ];
    }

    public function test_edicion_requiere_autenticacion(): void
    {
        $this->patchJson('/api/me', ['nombreusuario' => 'nuevo'])->assertUnauthorized();
    }

    public function test_usuario_sin_permisos_administrativos_puede_cambiar_su_nombre_una_vez(): void
    {
        $usuario = $this->crearUsuario();
        $headers = $this->bearer($usuario);

        $this->patchJson('/api/me', ['nombreusuario' => 'ana.mamani'], $headers)
            ->assertOk()
            ->assertJsonPath('nombreusuario', 'ana.mamani')
            ->assertJsonPath('nombreusuario_editado', true)
            ->assertJsonPath('profile_capabilities.update_username', false);

        $this->patchJson('/api/me', ['nombreusuario' => 'segundo.intento'], $headers)
            ->assertForbidden();
        $this->assertSame('ana.mamani', $usuario->fresh()->nombreusuario);
    }

    public function test_enviar_el_mismo_nombre_no_consume_el_cambio(): void
    {
        $usuario = $this->crearUsuario();
        $this->putJson('/api/me', ['nombreusuario' => 'perfil'], $this->bearer($usuario))
            ->assertOk()
            ->assertJsonPath('nombreusuario_editado', false);
    }

    #[DataProvider('nombresInvalidos')]
    public function test_rechaza_nombres_invalidos_sin_modificar_el_usuario(mixed $nombre): void
    {
        $usuario = $this->crearUsuario();
        $this->patchJson('/api/me', ['nombreusuario' => $nombre], $this->bearer($usuario))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('nombreusuario');
        $this->assertSame('perfil', $usuario->fresh()->nombreusuario);
        $this->assertFalse($usuario->fresh()->nombreusuario_editado);
    }

    public static function nombresInvalidos(): array
    {
        return [
            'vacio' => [''],
            'espacios internos' => ['ana mamani'],
            'simbolos' => ['ana@mamani'],
            'longitud' => [str_repeat('a', 101)],
            'tipo' => [['nombre' => 'ana']],
        ];
    }

    public function test_rechaza_nombre_duplicado_y_no_guarda_la_foto_del_mismo_envio(): void
    {
        $usuario = $this->crearUsuario();
        $this->crearUsuario('ocupado');

        $this->patch('/api/me', [
            'nombreusuario' => 'ocupado',
            'imagen' => UploadedFile::fake()->image('foto.png'),
        ], $this->bearer($usuario))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('nombreusuario');

        $this->assertSame('perfil', $usuario->fresh()->nombreusuario);
        $this->assertNull($usuario->fresh()->imagenurl);
        $this->assertCount(0, Storage::disk('public')->allFiles());
    }

    public function test_rechaza_campos_protegidos_y_un_id_ajeno_sin_cambios_parciales(): void
    {
        $usuario = $this->crearUsuario();
        $otro = $this->crearUsuario('otro');
        $hashAnterior = $usuario->passwordhash;

        $this->patchJson('/api/me', [
            'nombreusuario' => 'nuevo',
            'usuarioid' => $otro->usuarioid,
            'role' => 'admin',
            'roles' => ['admin'],
            'permissions' => ['usuarios.admin'],
            'email' => 'cambiado@example.test',
            'passwordhash' => 'inyectado',
            'activo' => false,
            'estado_cuenta' => CuentaEstado::PENDIENTE,
            'nombreusuario_editado' => false,
            'imagenurl' => '/storage/avatars/ajeno.png',
        ], $this->bearer($usuario))
            ->assertUnprocessable()
            ->assertJsonValidationErrors([
                'usuarioid', 'role', 'roles', 'permissions', 'email', 'passwordhash',
                'activo', 'estado_cuenta', 'nombreusuario_editado', 'imagenurl',
            ]);

        $usuario->refresh();
        $this->assertSame('perfil', $usuario->nombreusuario);
        $this->assertSame('perfil@example.test', $usuario->email);
        $this->assertSame($hashAnterior, $usuario->passwordhash);
        $this->assertTrue($usuario->activo);
        $this->assertFalse($usuario->nombreusuario_editado);
        $this->assertSame('otro', $otro->fresh()->nombreusuario);
    }

    public function test_rechaza_una_actualizacion_vacia(): void
    {
        $usuario = $this->crearUsuario();
        $this->patchJson('/api/me', [], $this->bearer($usuario))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('perfil');
    }

    public function test_permite_subir_foto_sin_cambiar_el_nombre_mediante_post_con_method(): void
    {
        $usuario = $this->crearUsuario();

        $response = $this->post('/api/me', [
            '_method' => 'PATCH',
            'imagen' => UploadedFile::fake()->image('foto.png'),
        ], $this->bearer($usuario));

        $response->assertOk()
            ->assertJsonPath('nombreusuario', 'perfil')
            ->assertJsonPath('nombreusuario_editado', false)
            ->assertJsonPath('profile_capabilities.update_photo', true);
        $path = ltrim($response->json('imagenurl'), '/');
        $this->assertStringStartsWith('storage/avatars/', $path);
        Storage::disk('public')->assertExists(substr($path, strlen('storage/')));
        $this->assertSame(url($path), $response->json('avatar_url'));
    }

    public function test_reemplaza_fotos_aunque_el_nombre_ya_este_bloqueado(): void
    {
        $usuario = $this->crearUsuario(atributos: ['nombreusuario_editado' => true]);
        $headers = $this->bearer($usuario);
        $primera = $this->patch('/api/me', ['imagen' => UploadedFile::fake()->image('foto.png')], $headers)
            ->assertOk()->json('imagenurl');
        $segunda = $this->patch('/api/me', ['imagen' => UploadedFile::fake()->image('foto.png')], $headers)
            ->assertOk()->json('imagenurl');

        $this->assertNotSame($primera, $segunda);
        Storage::disk('public')->assertMissing(substr($primera, strlen('/storage/')));
        Storage::disk('public')->assertExists(substr($segunda, strlen('/storage/')));
        $this->assertCount(1, Storage::disk('public')->allFiles('avatars'));
        $this->assertSame('perfil', $usuario->fresh()->nombreusuario);
    }

    public function test_un_segundo_nombre_impide_guardar_la_foto_del_mismo_envio(): void
    {
        $usuario = $this->crearUsuario(atributos: ['nombreusuario_editado' => true]);
        $this->patch('/api/me', [
            'nombreusuario' => 'no-permitido',
            'imagen' => UploadedFile::fake()->image('foto.png'),
        ], $this->bearer($usuario))->assertForbidden();

        $this->assertCount(0, Storage::disk('public')->allFiles());
        $this->assertNull($usuario->fresh()->imagenurl);
    }

    public function test_rechaza_archivos_que_no_son_imagenes(): void
    {
        $usuario = $this->crearUsuario();
        $this->patch('/api/me', [
            'imagen' => UploadedFile::fake()->create('foto.png', 10, 'application/pdf'),
        ], $this->bearer($usuario))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('imagen');
        $this->assertCount(0, Storage::disk('public')->allFiles());
    }

    public function test_rechaza_imagenes_mayores_a_dos_megabytes(): void
    {
        $usuario = $this->crearUsuario();
        $this->patch('/api/me', [
            'imagen' => UploadedFile::fake()->image('foto.jpg')->size(2049),
        ], $this->bearer($usuario))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('imagen');
        $this->assertNull($usuario->fresh()->imagenurl);
    }

    #[DataProvider('cuentasNoAutorizadas')]
    public function test_rechaza_cuentas_no_autorizadas(bool $activo, string $estado): void
    {
        $usuario = $this->crearUsuario();
        $headers = $this->bearer($usuario);
        $usuario->update(['activo' => $activo, 'estado_cuenta' => $estado]);

        $this->patchJson('/api/me', ['nombreusuario' => 'nuevo'], $headers)->assertForbidden();
        $this->assertSame('perfil', $usuario->fresh()->nombreusuario);
    }

    public static function cuentasNoAutorizadas(): array
    {
        return [
            'inactiva' => [false, CuentaEstado::APROBADO],
            'pendiente' => [true, CuentaEstado::PENDIENTE],
        ];
    }

    public function test_fallo_al_escribir_la_imagen_conserva_el_perfil_y_la_foto_anterior(): void
    {
        Storage::disk('public')->put('avatars/anterior.png', 'foto anterior');
        $usuario = $this->crearUsuario(atributos: ['imagenurl' => '/storage/avatars/anterior.png']);
        $imagen = Mockery::mock(UploadedFile::class);
        $imagen->shouldReceive('extension')->andReturn('png');
        $imagen->shouldReceive('storeAs')->once()->andReturn(false);

        try {
            app(PerfilUsuarioService::class)->actualizar($usuario, [
                'nombreusuario' => 'nuevo',
                'imagen' => $imagen,
            ]);
            $this->fail('El fallo de almacenamiento debe impedir guardar el perfil.');
        } catch (RuntimeException $exception) {
            $this->assertSame('No se pudo guardar la foto de perfil.', $exception->getMessage());
        }

        $usuario->refresh();
        $this->assertSame('perfil', $usuario->nombreusuario);
        $this->assertFalse($usuario->nombreusuario_editado);
        $this->assertSame('/storage/avatars/anterior.png', $usuario->imagenurl);
        Storage::disk('public')->assertExists('avatars/anterior.png');
    }

    public function test_fallo_de_transaccion_elimina_la_foto_nueva_y_conserva_la_anterior(): void
    {
        Storage::disk('public')->put('avatars/anterior.png', 'foto anterior');
        $usuario = $this->crearUsuario(atributos: ['imagenurl' => '/storage/avatars/anterior.png']);
        $connection = DB::connection();
        DB::partialMock()->shouldReceive('transaction')->once()->andReturnUsing(
            fn ($callback) => $connection->transaction(function () use ($callback) {
                $callback();
                throw new RuntimeException('Fallo de transacción simulado');
            })
        );

        try {
            app(PerfilUsuarioService::class)->actualizar($usuario, [
                'imagen' => UploadedFile::fake()->image('nueva.png'),
            ]);
            $this->fail('La transacción debe fallar.');
        } catch (RuntimeException $exception) {
            $this->assertSame('Fallo de transacción simulado', $exception->getMessage());
        }

        $this->assertSame('/storage/avatars/anterior.png', $usuario->fresh()->imagenurl);
        Storage::disk('public')->assertExists('avatars/anterior.png');
        $this->assertSame(['avatars/anterior.png'], Storage::disk('public')->allFiles('avatars'));
    }
}
