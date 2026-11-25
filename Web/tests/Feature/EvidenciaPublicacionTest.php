<?php

namespace Tests\Feature;

use App\Models\Actividad;
use App\Models\EvidenciaPublicacion;
use App\Models\EvidenciaPublicacionEvento;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\Support\CertificadosFixture;
use Tests\Support\TrazabilidadPublicaFixture;
use Tests\TestCase;

class EvidenciaPublicacionTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    private Actividad $actividad;

    private $jefe;

    private $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        Storage::fake('local');
        $this->f = TrazabilidadPublicaFixture::crear();
        $this->jefe = $this->f['usuario'];
        $this->jefe->syncRoles(['jefe_agricultor']);
        $this->admin = CertificadosFixture::usuario('admin', 'adminPublicacion61');
        $this->actividad = Actividad::create(['loteid' => $this->f['lote']->getKey(), 'usuarioid' => $this->jefe->getKey(),
            'tipoactividadid' => TipoActividad::create(['nombre' => 'Riego'])->getKey(),
            'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->getKey(),
            'descripcion' => 'NOTA-PRIVADA-DEL-REPORTE-61', 'fechainicio' => now()->subHour(), 'fechafin' => now()]);
        $path = 'actividades_privadas/'.$this->actividad->getKey().'/foto.png';
        $bytes = UploadedFile::fake()->image('foto.png', 12, 12)->getContent();
        $texto = 'Comentario'.chr(0).'GPS-METADATO-PRIVADO-61';
        $chunk = pack('N', strlen($texto)).'tEXt'.$texto.pack('N', crc32('tEXt'.$texto));
        Storage::disk('local')->put($path, substr($bytes, 0, -12).$chunk.substr($bytes, -12));
        $this->actividad->update(['evidencia_foto_path' => $path]);
    }

    private function solicitar(): EvidenciaPublicacion
    {
        $this->actingAs($this->jefe)->postJson('/api/evidencias-publicacion/actividades/'.$this->actividad->getKey().'/solicitar',
            ['motivo' => 'MOTIVO-PRIVADO-61: revisión de fotografía sin datos personales.'])->assertCreated();

        return EvidenciaPublicacion::firstOrFail();
    }

    private function url(): string
    {
        return '/api/trazabilidad/'.$this->f['lote']->codigo_trazabilidad;
    }

    public function test_fotos_son_privadas_por_defecto_y_solo_admin_con_permiso_publica_copia_sanitizada(): void
    {
        $this->get($this->url())->assertOk()->assertJsonCount(0, 'evidencias')
            ->assertJsonPath('estado_evidencias', 'sin_evidencias_publicas_disponibles');
        $p = $this->solicitar();
        $this->assertNull($p->archivo_sanitizado);
        $this->get($this->url())->assertJsonCount(0, 'evidencias');
        $publica = route('api.trazabilidad.evidencia', $p->token_publico, false);
        $this->get($publica)->assertNotFound();
        $this->postJson('/api/evidencias-publicacion/'.$p->getKey().'/aprobar', ['motivo' => 'Sin permiso'])->assertForbidden();
        $this->actingAs($this->admin)->postJson('/api/evidencias-publicacion/'.$p->getKey().'/aprobar',
            ['motivo' => 'Revisión explícita: apta para difusión pública.'])->assertOk()->assertJsonPath('estado', 'publicada');
        $respuesta = $this->get($this->url())->assertOk()->assertJsonCount(1, 'evidencias')
            ->assertJsonPath('estado_evidencias', 'con_evidencias_publicas');
        foreach (['MOTIVO-PRIVADO-61', 'NOTA-PRIVADA-DEL-REPORTE-61', 'actividades_privadas', 'archivo_sanitizado', 'usuarioid'] as $secreto) {
            $this->assertStringNotContainsString($secreto, $respuesta->getContent());
        }
        $imagen = $this->get($publica)->assertOk()->assertHeader('content-type', 'image/png');
        $this->assertStringContainsString('no-store', $imagen->headers->get('Cache-Control'));
        $bytes = file_get_contents($imagen->baseResponse->getFile()->getPathname());
        $this->assertStringNotContainsString('GPS-METADATO-PRIVADO-61', $bytes);
        $this->assertNotSame(Storage::disk('local')->get($this->actividad->evidencia_foto_path), $bytes);
        $this->assertSame($this->admin->getKey(), EvidenciaPublicacionEvento::where('accion', 'aprobar')->sole()->usuarioid);
    }

    public function test_retiro_quita_acceso_publico_y_conserva_quien_cuando_y_motivo_sin_duplicar_reintentos(): void
    {
        $p = $this->solicitar();
        $this->actingAs($this->admin)->postJson('/api/evidencias-publicacion/'.$p->getKey().'/aprobar', ['motivo' => 'Aprobada'])->assertOk();
        $this->postJson('/api/evidencias-publicacion/'.$p->getKey().'/aprobar', ['motivo' => 'Aprobada'])->assertOk();
        $otra = $p->fresh()->replicate();
        $otra->fill(['estado' => 'solicitada', 'token_publico' => (string) \Illuminate\Support\Str::uuid(), 'archivo_sanitizado' => null, 'aprobado_en' => null]);
        $otra->save();
        $this->postJson('/api/evidencias-publicacion/'.$otra->getKey().'/aprobar', ['motivo' => 'Otra solicitud del mismo archivo'])->assertConflict();
        $this->actingAs($this->jefe)->postJson('/api/evidencias-publicacion/'.$p->getKey().'/solicitar-retiro', ['motivo' => 'Solicito retirar esta foto'])->assertOk();
        $this->get($this->url())->assertJsonCount(1, 'evidencias');
        $this->actingAs($this->admin)->postJson('/api/evidencias-publicacion/'.$p->getKey().'/retirar', ['motivo' => 'Retirada tras revisión'])->assertOk();
        $this->postJson('/api/evidencias-publicacion/'.$p->getKey().'/retirar', ['motivo' => 'Retirada tras revisión'])->assertOk();
        $this->get($this->url())->assertJsonCount(0, 'evidencias');
        $this->get(route('api.trazabilidad.evidencia', $p->token_publico, false))->assertNotFound();
        $this->assertCount(4, $p->fresh()->eventos);
        $evento = EvidenciaPublicacionEvento::where('accion', 'retirar')->sole();
        $this->assertSame($this->admin->getKey(), $evento->usuarioid);
        $this->assertSame('Retirada tras revisión', $evento->motivo);
        $this->assertNotNull($evento->fecha);
        Storage::disk('local')->assertExists($p->fresh()->archivo_sanitizado);
    }

    public function test_no_se_aprueba_una_version_que_cambio_y_archivos_ausentes_no_rompen_trazabilidad(): void
    {
        $p = $this->solicitar();
        Storage::disk('local')->put($this->actividad->evidencia_foto_path, UploadedFile::fake()->image('otra.png', 15, 15)->getContent());
        $this->actingAs($this->admin)->postJson('/api/evidencias-publicacion/'.$p->getKey().'/aprobar', ['motivo' => 'Revisada'])->assertUnprocessable();
        $this->assertSame('solicitada', $p->fresh()->estado);
        $this->assertNull($p->fresh()->archivo_sanitizado);
        Storage::disk('local')->delete($this->actividad->evidencia_foto_path);
        $this->get($this->url())->assertOk()->assertJsonCount(0, 'evidencias');
    }

    public function test_solicitudes_revisiones_y_auditoria_restringen_ambito_y_permiso(): void
    {
        $p = $this->solicitar();
        $ajeno = CertificadosFixture::usuario('jefe_agricultor', 'otroPublicacion61');
        $this->actingAs($ajeno)->postJson('/api/evidencias-publicacion/actividades/'.$this->actividad->getKey().'/solicitar', ['motivo' => 'Ajeno'])->assertNotFound();
        $this->getJson('/api/evidencias-publicacion')->assertOk()->assertJsonPath('total', 0);
        $this->get('/api/evidencias-publicacion/'.$p->getKey().'/archivo')->assertNotFound();
        $this->actingAs($this->jefe)->get('/api/evidencias-publicacion/'.$p->getKey().'/archivo')->assertOk();
        $rol = $this->admin->roles->first();
        $rol->revokePermissionTo('evidencias.publicar');
        $this->admin->unsetRelation('roles');
        $this->actingAs($this->admin)->postJson('/api/evidencias-publicacion/'.$p->getKey().'/aprobar', ['motivo' => 'Sin permiso específico'])->assertForbidden();
        $this->assertSame('solicitada', $p->fresh()->estado);
        $this->actingAs($this->jefe)->postJson('/api/evidencias-publicacion/actividades/'.$this->actividad->getKey().'/solicitar', ['motivo' => '  '])->assertUnprocessable();
        $this->jefe->update(['activo' => false]);
        $this->getJson('/api/evidencias-publicacion')->assertForbidden();
        $this->postJson('/api/evidencias-publicacion/actividades/'.$this->actividad->getKey().'/solicitar', ['motivo' => 'Cuenta inactiva'])->assertForbidden();
        $this->jefe->update(['activo' => true]);
        $this->jefe->roles->first()->revokePermissionTo('lotes.view');
        $this->jefe->unsetRelation('roles');
        $this->postJson('/api/evidencias-publicacion/actividades/'.$this->actividad->getKey().'/solicitar', ['motivo' => 'Sin consulta del origen'])->assertForbidden();
    }

    public function test_jefe_planta_solicita_solo_evidencia_de_un_origen_con_fk_dentro_de_su_produccion(): void
    {
        $f = CertificadosFixture::crear();
        $actividad = $f['campos'][0]->actividades()->firstOrFail();
        $path = 'actividades_privadas/'.$actividad->getKey().'/foto.png';
        Storage::disk('local')->put($path, UploadedFile::fake()->image('foto.png')->getContent());
        $actividad->update(['evidencia_foto_path' => $path]);
        $this->actingAs($f['planta'])->postJson('/api/evidencias-publicacion/actividades/'.$actividad->getKey().'/solicitar',
            ['motivo' => 'Revisión del origen recibido', 'loteproduccionpedidoid' => $f['lote']->getKey()])->assertCreated();
        $this->postJson('/api/evidencias-publicacion/actividades/'.$this->actividad->getKey().'/solicitar',
            ['motivo' => 'Foto ajena', 'loteproduccionpedidoid' => $f['lote']->getKey()])->assertNotFound();
        $p = EvidenciaPublicacion::where('actividadid', $actividad->getKey())->sole();
        $this->actingAs($this->admin)->postJson('/api/evidencias-publicacion/'.$p->getKey().'/aprobar', ['motivo' => 'Apta'])->assertOk();
        $this->actingAs($f['agricola'])->postJson('/api/evidencias-publicacion/'.$p->getKey().'/solicitar-retiro',
            ['motivo' => 'El propietario del origen solicita el retiro'])->assertOk()->assertJsonPath('estado', 'retiro_solicitado');
    }
}
