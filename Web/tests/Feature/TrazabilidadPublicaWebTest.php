<?php

namespace Tests\Feature;

use App\Models\Actividad;
use App\Models\CertificacionLote;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use App\Services\ConsultaTrazabilidadPublicaService;
use App\Services\EvidenciaPublicacionService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Storage;
use Tests\Support\CertificadosFixture;
use Tests\Support\TrazabilidadPublicaFixture;
use Tests\TestCase;

class TrazabilidadPublicaWebTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    protected function setUp(): void
    {
        parent::setUp();
        $this->f = TrazabilidadPublicaFixture::crear();
        $this->withServerVariables(['REMOTE_ADDR' => '198.51.100.62']);
        Http::preventStrayRequests();
    }

    private function detalle(string $codigo): string
    {
        return route('trazabilidad.publica', ['codigo' => $codigo]);
    }

    public function test_login_y_buscador_son_publicos_y_formulario_get(): void
    {
        $this->get('/login')->assertOk()->assertSee('Consultar trazabilidad')->assertSee(route('trazabilidad.buscar'));
        $this->get('/trazabilidad')->assertOk()->assertSee('Código de trazabilidad')
            ->assertSee('method="GET"', false)->assertSee('name="codigo"', false)->assertSee('Consultar');
    }

    public function test_busqueda_normalizada_y_detalle_de_ambos_tipos_coinciden_con_api(): void
    {
        foreach ([$this->f['lote'], $this->f['pdv']] as $modelo) {
            $codigo = $modelo->codigo_trazabilidad;
            $this->get('/trazabilidad?'.http_build_query(['codigo' => ' '.strtolower($codigo).' ']))
                ->assertRedirect($this->detalle($codigo));
            $json = $this->get('/api/trazabilidad/'.$codigo)->assertOk()->json();
            $this->get($this->detalle(strtolower($codigo)))->assertOk()->assertViewHas('reporte', $json)
                ->assertSee($codigo)->assertSee('Sin información registrada para esta etapa.')
                ->assertSee('No hay evidencias públicas disponibles.')->assertDontSee('Producto Certificado');
        }
    }

    public function test_validacion_conserva_valor_escapado_sin_redirigir_a_urls_externas(): void
    {
        foreach (['', 'incorrecto', '<script>alert(62)</script>', str_repeat('A', 90), 'https://example.test'] as $codigo) {
            $this->get('/trazabilidad?'.http_build_query(['codigo' => $codigo, 'redirect' => 'https://example.test']))
                ->assertUnprocessable()->assertSee('id="codigo-error"', false)
                ->assertSee('value="'.e($codigo).'"', false)->assertDontSee('<script>alert(62)</script>', false);
        }
        $this->get('/trazabilidad?codigo[]=abc')->assertUnprocessable()->assertSee('Escribe un código');
        $this->get($this->detalle('incorrecto'))->assertUnprocessable()->assertSee('incorrecto');
    }

    public function test_codigo_inexistente_devuelve_404_amigable_y_permite_corregir(): void
    {
        $this->get($this->detalle('TRAZ-20261125-NOEXIS'))->assertNotFound()
            ->assertSee('Código no encontrado')->assertSee('value="TRAZ-20261125-NOEXIS"', false)
            ->assertSee('Volver al buscador')->assertSee('method="GET"', false);
        $this->get('/trazabilidad?codigo='.$this->f['lote']->codigo_trazabilidad)
            ->assertRedirect($this->detalle($this->f['lote']->codigo_trazabilidad));
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk();
    }

    public function test_datos_privados_y_html_de_usuario_no_aparecen_sin_escapar(): void
    {
        $this->f['lote']->update(['nombre' => '<script>alert(62)</script>']);
        $html = $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk()
            ->assertSee('&lt;script&gt;alert(62)&lt;/script&gt;', false)->assertDontSee('<script>alert(62)</script>', false)
            ->getContent();
        foreach (['IDENTIDAD-PRIVADA-61', 'privado61@example.test', 'TEL-PRIVADO-61', 'HASH-PRIVADO-61',
            'DOMICILIO-PRIVADO-61', '-17.123456', '-63.987654', 'FOTO-PRIVADA-61', 'NOTA-USUARIO-PRIVADA-61'] as $secreto) {
            $this->assertStringNotContainsString($secreto, $html);
        }
    }

    public function test_historial_real_sin_asumir_vigencia_ni_confirmar_un_hash_pendiente(): void
    {
        foreach (['CERT-62-A' => ['resultado' => 'Certificado', 'blockchain_estado' => 'pendiente', 'blockchain_hash' => str_repeat('a', 64)],
            'CERT-62-B' => ['resultado' => 'No conforme', 'blockchain_estado' => 'error']] as $codigo => $extra) {
            (new CertificacionLote)->forceFill([
                'loteid' => $this->f['lote']->getKey(), 'usuarioid' => $this->f['usuario']->getKey(),
                'codigo_certificado' => $codigo, 'fecha_certificacion' => now(),
                'observaciones' => 'CERT-NOTA-PRIVADA-62', 'archivo_path' => 'private/CERT-PRIVADO-62.pdf',
                'blockchain_error' => 'RPC-SECRETO-62', ...$extra,
            ])->save();
        }
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk()
            ->assertSee('CERT-62-A')->assertSee('CERT-62-B')->assertSee('No conforme')
            ->assertSee('No determinada:')->assertSee('Pendiente de confirmación')->assertSee('Error registrado')
            ->assertSee('Sin confirmación registrada')->assertSee(str_repeat('a', 64))
            ->assertSee('Hash del documento')->assertSee('Hash de transacción')
            ->assertDontSee('RPC-SECRETO-62')->assertDontSee('CERT-NOTA-PRIVADA-62')->assertDontSee('CERT-PRIVADO-62.pdf')
            ->assertDontSee('Producto Certificado');
        Http::assertNothingSent();
    }

    public function test_evidencia_solo_aprobada_y_retiro_quita_html_y_acceso_publico(): void
    {
        Storage::fake('local');
        $this->seed(RolePermissionSeeder::class);
        $jefe = $this->f['usuario'];
        $jefe->syncRoles(['jefe_agricultor']);
        $admin = CertificadosFixture::usuario('admin', 'publicador62');
        $actividad = Actividad::create(['loteid' => $this->f['lote']->getKey(), 'usuarioid' => $jefe->getKey(),
            'tipoactividadid' => TipoActividad::create(['nombre' => 'Riego'])->getKey(),
            'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->getKey(),
            'descripcion' => 'DESCRIPCION-PRIVADA-62', 'fechainicio' => now()]);
        $path = 'actividades_privadas/'.$actividad->getKey().'/foto.png';
        Storage::disk('local')->put($path, UploadedFile::fake()->image('foto.png', 12, 12)->getContent());
        $actividad->update(['evidencia_foto_path' => $path]);
        $service = app(EvidenciaPublicacionService::class);
        $publicacion = $service->solicitar($jefe, $actividad, 'Revisar fotografía');
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk()
            ->assertSee('No hay evidencias públicas disponibles.')->assertDontSee($path);
        $service->aprobar($admin, $publicacion->getKey(), 'Revisión explícita completada');
        $url = route('api.trazabilidad.evidencia', ['token' => $publicacion->fresh()->token_publico]);
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk()->assertSee($url)
            ->assertDontSee($path)->assertDontSee('DESCRIPCION-PRIVADA-62');
        $this->get($url)->assertOk();
        $service->retirar($admin, $publicacion->getKey(), 'Retirar difusión pública');
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk()->assertDontSee($url);
        $this->get($url)->assertNotFound();
    }

    public function test_limite_web_legible_y_api_conserva_json_y_estados(): void
    {
        // Exercise the actual named limiter without sending 60 duplicate page queries.
        $key = 'trazabilidad-publica:'.hash('sha256', '198.51.100.62');
        for ($i = 0; $i < 60; $i++) {
            RateLimiter::hit(md5('trazabilidad-publica'.$key), 60);
        }
        $this->get('/trazabilidad?codigo=corregir')->assertStatus(429)->assertSee('Límite de consultas alcanzado')
            ->assertSee('corregir')->assertHeader('Retry-After');
        $this->get('/api/trazabilidad/'.$this->f['lote']->codigo_trazabilidad)->assertStatus(429)
            ->assertHeader('content-type', 'application/json')->assertJsonStructure(['message']);
    }

    public function test_consultar_no_escribe_datos_y_rutas_privadas_siguen_protegidas(): void
    {
        $escrituras = [];
        DB::listen(function (QueryExecuted $query) use (&$escrituras) {
            if (preg_match('/^\s*(insert|update|delete|replace|alter|create|drop)\b/i', $query->sql)) {
                $escrituras[] = $query->sql;
            }
        });
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk();
        $this->get($this->detalle($this->f['pdv']->codigo_trazabilidad))->assertOk();
        $this->get('/api/trazabilidad/'.$this->f['lote']->codigo_trazabilidad)->assertOk();
        $this->assertSame([], $escrituras);
        $this->get('/consulta-recorrido')->assertRedirect('/login');
        $this->getJson('/api/evidencias-publicacion')->assertUnauthorized();
    }

    public function test_fallo_interno_no_se_disfraza_como_codigo_inexistente(): void
    {
        $this->mock(ConsultaTrazabilidadPublicaService::class)->shouldReceive('consultar')->once()
            ->andThrow(new \RuntimeException('ERROR-INTERNO-NO-PUBLICAR-62'));
        config(['app.debug' => false]);
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertStatus(500)
            ->assertDontSee('Código no encontrado')->assertDontSee('ERROR-INTERNO-NO-PUBLICAR-62');
    }

    public function test_pdv_muestra_multiorigen_cantidades_y_misma_proyeccion_publica_sin_antecedentes_ajenos(): void
    {
        $this->seed(RolePermissionSeeder::class);
        $real = CertificadosFixture::crear();
        foreach ($real['campos'] as $i => $campo) {
            $campo->update(['codigo_trazabilidad' => 'TRAZ-20261125-ORIG0'.$i]);
            $campo->actividades()->update(['observaciones' => 'OBSERVACION-PRIVADA-62',
                'descripcion' => 'ACTIVIDAD-PRIVADA-62', 'evidencia_foto_path' => 'private/FOTO-AJENA-62.jpg']);
        }
        $this->f['pdv']->update(['almacenid' => $real['almacen']->getKey()]);
        $presentacion = InsumoPresentacion::create(['insumoid' => $this->f['pdv']->getKey(),
            'nombre' => 'Bolsa 1 kg', 'peso_neto_kg' => 1, 'tipo_envase' => 'bolsa', 'activo' => true]);
        InventarioPresentacionLote::create(['insumoid' => $this->f['pdv']->getKey(),
            'almacenid' => $real['almacen']->getKey(), 'insumo_presentacionid' => $presentacion->getKey(),
            'loteproduccionpedidoid' => $real['lote']->getKey(), 'cantidad_unidades' => '2.123456', 'cantidad_kg' => '2.123456']);
        $json = $this->get('/api/trazabilidad/'.$this->f['pdv']->codigo_trazabilidad)->assertOk()->json();
        $this->assertCount(2, $json['origenes']);
        $html = $this->get($this->detalle($this->f['pdv']->codigo_trazabilidad))->assertOk()
            ->assertViewHas('reporte', $json)->assertSee('TRAZ-20261125-ORIG00')->assertSee('TRAZ-20261125-ORIG01')
            ->assertSee('5.123000 kg')->assertSee('Bolsa 1 kg')->assertDontSee('OBSERVACION-PRIVADA-62')
            ->assertDontSee('ACTIVIDAD-PRIVADA-62')->assertDontSee('FOTO-AJENA-62.jpg')->getContent();
        foreach ([$real['agricola']->email, $real['planta']->email, $real['operario']->email] as $secreto) {
            $this->assertStringNotContainsString($secreto, $html);
        }
    }

    public function test_confirmacion_local_exige_tx_y_no_se_confunde_con_verificacion_en_vivo(): void
    {
        $emision = new CertificacionLote;
        $emision->forceFill(['loteid' => $this->f['lote']->getKey(), 'usuarioid' => $this->f['usuario']->getKey(),
            'codigo_certificado' => 'CERT-62-CONF', 'resultado' => 'Certificado', 'fecha_certificacion' => now(),
            'blockchain_estado' => 'certificada', 'blockchain_hash' => str_repeat('b', 64)])->save();
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk()
            ->assertSee('Sin confirmación registrada')->assertDontSee('Confirmación registrada en el sistema');
        $emision->forceFill(['blockchain_txid' => '0x'.str_repeat('c', 64)])->save();
        $this->get($this->detalle($this->f['lote']->codigo_trazabilidad))->assertOk()
            ->assertSee('Confirmación registrada en el sistema')->assertSee('sin verificación en vivo')
            ->assertSee('0x'.str_repeat('c', 64));
        Http::assertNothingSent();
    }
}
