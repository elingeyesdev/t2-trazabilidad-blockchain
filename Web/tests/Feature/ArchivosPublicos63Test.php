<?php

namespace Tests\Feature;

use App\Models\Actividad;
use App\Models\DocumentoEntrega;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use App\Services\EvidenciaPublicacionService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\Support\CertificadosFixture;
use Tests\Support\TrazabilidadPublicaFixture;
use Tests\TestCase;

class ArchivosPublicos63Test extends TestCase
{
    use RefreshDatabase;

    public function test_publicacion_aprobada_funciona_sin_sesion_y_no_aparece_en_otro_producto_y_retiro_la_bloquea(): void
    {
        $this->seed(RolePermissionSeeder::class);
        Storage::fake('local');
        $f = TrazabilidadPublicaFixture::crear();
        $f['usuario']->update(['role' => 'jefe_agricultor']);
        $f['usuario']->syncRoles(['jefe_agricultor']);
        $admin = CertificadosFixture::usuario('admin', 'publicador63');
        $actividad = Actividad::create(['loteid' => $f['lote']->getKey(), 'usuarioid' => $f['usuario']->getKey(), 'descripcion' => 'NOTA-PRIVADA-63',
            'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => 'Riego'])->getKey(),
            'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->getKey(), 'fechainicio' => now(), 'fechafin' => now()]);
        $path = 'actividades_privadas/'.$actividad->getKey().'/foto.png';
        Storage::disk('local')->put($path, UploadedFile::fake()->image('foto.png', 8, 8)->getContent());
        $actividad->update(['evidencia_foto_path' => $path]);
        $service = app(EvidenciaPublicacionService::class);
        $p = $service->solicitar($f['usuario'], $actividad, 'Revisión solicitada');
        $url = route('api.trazabilidad.evidencia', ['token' => $p->token_publico], false);
        $this->get($url)->assertNotFound();
        $service->aprobar($admin, $p->getKey(), 'Aprobada explícitamente');
        $this->assertGuest();
        $this->get($url)->assertOk()->assertHeader('content-type', 'image/png')
            ->assertDontSee('actividades_privadas')->assertHeader('X-Content-Type-Options', 'nosniff');
        $this->getJson('/api/trazabilidad/'.$f['lote']->codigo_trazabilidad)->assertOk()->assertJsonCount(1, 'evidencias');
        $otro = $f['lote']->replicate();
        $otro->codigo_trazabilidad = 'TRAZ-20261125-AJENO6';
        $otro->save();
        $this->getJson('/api/trazabilidad/'.$otro->codigo_trazabilidad)->assertOk()->assertJsonCount(0, 'evidencias');
        $this->getJson('/api/actividades/'.$actividad->getKey().'/evidencia')->assertUnauthorized();
        $service->retirar($admin, $p->getKey(), 'Retiro solicitado');
        $this->get($url)->assertNotFound();
        $this->getJson('/api/trazabilidad/'.$f['lote']->codigo_trazabilidad)->assertJsonCount(0, 'evidencias');
        $actividad->update(['evidencia_foto_path' => '../../.env']);
        $this->get($url)->assertNotFound();
        $this->get('/api/trazabilidad/evidencias/'.rawurlencode('../.env'))->assertNotFound();
    }

    public function test_documento_interno_exige_autenticacion_y_ambito_y_no_acepta_ruta_arbitraria(): void
    {
        $this->seed(RolePermissionSeeder::class);
        Storage::fake('public');
        $admin = CertificadosFixture::usuario('admin', 'adminDoc63');
        $otro = CertificadosFixture::usuario('transportista', 'otroDoc63');
        Storage::disk('public')->put('documentos_entrega/interno63.pdf', '%PDF-1.4 DOCUMENTO-INTERNO-63');
        $doc = DocumentoEntrega::create(['titulo' => 'Documento interno', 'tipo_documento' => 'guia_transporte',
            'usuarioid' => $admin->getKey(), 'archivo_path' => 'documentos_entrega/interno63.pdf',
            'metadata' => ['original_name' => 'documento.pdf']]);
        $url = '/api/documentos-entrega/'.$doc->getKey().'/download';
        $this->getJson($url)->assertUnauthorized();
        $this->actingAs($otro)->getJson($url)->assertForbidden();
        $this->actingAs($admin)->getJson($url)->assertOk();
        $doc->update(['archivo_path' => '../../.env']);
        $this->getJson($url)->assertNotFound();
    }
}
