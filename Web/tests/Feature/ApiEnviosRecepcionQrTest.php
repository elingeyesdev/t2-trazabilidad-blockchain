<?php

namespace Tests\Feature;

use App\Models\AlmacenMovimiento;
use App\Models\FirmaRecepcionEnvio;
use App\Models\Insumo;
use App\Models\PedidoDistribucion;
use App\Models\RecepcionQrEnvio;
use App\Services\EnvioMovilConsultaService;
use App\Services\EnvioRecepcionQrService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Support\CertificadosFixture;
use Tests\Support\EnvioQrFixture;
use Tests\TestCase;

class ApiEnviosRecepcionQrTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        Storage::fake('local');
    }

    private function payload(array $f): array
    {
        return ['codigo' => $f['qr']->token, 'imagen_firma' => EnvioQrFixture::firma(),
            'lineas' => array_map(fn ($l) => ['id' => $l['id'], 'cantidad_recibida' => $l['cantidad_enviada']], app(EnvioMovilConsultaService::class)->lineas($f['envio'], $f['receptor']))];
    }

    private function confirmar(array $f, ?array $payload = null)
    {
        return $this->actingAs($f['receptor'])->postJson('/api/envios/'.$f['tipo'].'/'.$f['envio']->getKey().'/recepcion', $payload ?? $this->payload($f));
    }

    public function test_consulta_y_resolucion_autorizadas_no_consumen_qr_ni_exponen_secretos(): void
    {
        foreach (['agricola', 'distribucion', 'traslado'] as $tipo) {
            $f = EnvioQrFixture::crear($tipo);
            $antes = AlmacenMovimiento::count();
            $this->actingAs($f['receptor'])->getJson('/api/envios/'.$tipo)->assertOk()->assertJsonPath('meta.total', 1);
            $this->getJson('/api/envios/'.$tipo.'/'.$f['envio']->getKey())->assertOk()->assertJsonPath('data.estado', $f['envio']->estado)->assertJsonCount(1, 'data.lineas');
            $res = $this->postJson('/api/envios/qr/resolver', ['codigo' => app(EnvioRecepcionQrService::class)->url($f['qr'])])->assertOk()->assertJsonPath('data.utilizado', false);
            $this->assertStringNotContainsString($f['qr']->token, $res->getContent());
            $this->assertNull($f['qr']->fresh()->utilizado_en);
            $this->assertSame($antes, AlmacenMovimiento::count());
            $this->assertNotSame($f['qr']->token, $f['qr']->getRawOriginal('token'));
        }
    }

    public function test_confirma_tres_flujos_y_conserva_datos_firma_y_comprobante(): void
    {
        foreach (['agricola', 'distribucion', 'traslado'] as $tipo) {
            $f = EnvioQrFixture::crear($tipo);
            $res = $this->confirmar($f)->assertCreated()->assertJsonPath('data.firmante.id', $f['receptor']->getKey());
            $qr = $f['qr']->fresh();
            $this->assertNotNull($qr->utilizado_en);
            Storage::disk('local')->assertExists($qr->firma_path);
            $destinoId = $tipo === 'distribucion' ? $f['pdv']->fresh()->almacenid : $f['almacen']->getKey();
            $esperadoKg = $tipo === 'agricola' ? '10.123456' : ($tipo === 'distribucion' ? '10.246912' : '10.000000');
            $this->assertSame($esperadoKg, (string) \Brick\Math\BigDecimal::of(Insumo::where('almacenid', $destinoId)->firstOrFail()->getRawOriginal('stock'))->toScale(6));
            if ($tipo === 'distribucion') {
                $this->assertEquals(100, $f['insumo']->fresh()->getRawOriginal('stock'));
            }
            $this->assertSame((string) \Brick\Math\BigDecimal::of($this->payload($f)['lineas'][0]['cantidad_recibida'])->toScale(6), $res->json('data.lineas.0.cantidad_recibida'));
            $this->getJson('/api/recepciones-envio/'.$qr->getKey())->assertOk()->assertJsonPath('data.envio.referencia', $f['envio']->externo_envio_id ?? $f['envio']->codigo);
            $this->get('/api/recepciones-envio/'.$qr->getKey().'/firma')->assertOk()->assertHeader('Content-Type', 'image/png');
            $pdf = $this->get('/api/recepciones-envio/'.$qr->getKey().'/comprobante')->assertOk();
            $this->assertStringStartsWith('%PDF-', $pdf->getContent());
            $this->get(route('recepcion.comprobante', $qr->getKey()))->assertOk();
            $this->assertSame($tipo === 'agricola' ? 'recibido_planta' : 'completada', $f['envio']->fresh()->estado);
        }
    }

    public function test_repeticion_y_respuesta_perdida_no_duplican_recepcion_ni_movimientos(): void
    {
        $f = EnvioQrFixture::crear();
        $this->confirmar($f)->assertCreated();
        $antes = AlmacenMovimiento::count();
        $archivos = Storage::disk('local')->allFiles();
        $this->confirmar($f)->assertConflict()->assertSee('ya fue utilizado');
        $this->actingAs($f['receptor'])->getJson('/api/recepciones-envio/'.$f['qr']->getKey())->assertOk()->assertJsonCount(1, 'data.lineas');
        $this->assertSame($antes, AlmacenMovimiento::count());
        $this->assertSame($archivos, Storage::disk('local')->allFiles());
        $this->assertSame(1, FirmaRecepcionEnvio::count());
    }

    public function test_cada_destinatario_tiene_codigo_y_recibe_solo_sus_pedidos(): void
    {
        $f = EnvioQrFixture::crear('distribucion', true);
        $this->assertCount(2, $f['qrs']);
        $this->actingAs($f['receptor'])->postJson('/api/envios/qr/resolver', ['codigo' => $f['qr']->token])->assertOk()->assertJsonCount(1, 'data.envio.lineas')->assertJsonCount(1, 'data.envio.destinos');
        $otroQr = collect($f['qrs'])->first(fn ($q) => $q->getKey() !== $f['qr']->getKey());
        $this->postJson('/api/envios/qr/resolver', ['codigo' => $otroQr->token])->assertNotFound();
        $this->confirmar($f)->assertCreated();
        $this->assertSame('en_ruta', $f['envio']->fresh()->estado);
        $this->assertSame(1, PedidoDistribucion::where('estado', 'recibido')->count());
        $this->assertNull($otroQr->fresh()->utilizado_en);
        $f['receptor'] = $f['otroReceptor'];
        $f['qr'] = $otroQr;
        $this->confirmar($f)->assertCreated();
        $this->assertSame('completada', $f['envio']->fresh()->estado);
        $this->assertSame(2, PedidoDistribucion::where('estado', 'recibido')->count());
        $this->assertSame(2, RecepcionQrEnvio::whereNotNull('utilizado_en')->count());
    }

    public function test_remitente_transportista_admin_y_usuario_ajeno_no_confirman(): void
    {
        $f = EnvioQrFixture::crear();
        foreach ([$f['remitente'], $f['conductor'], CertificadosFixture::usuario('admin', 'admin52'), CertificadosFixture::usuario('jefe_planta', 'ajeno52')] as $user) {
            $this->actingAs($user)->postJson('/api/envios/agricola/'.$f['envio']->getKey().'/recepcion', $this->payload($f))->assertStatus(in_array($user->getKey(), [$f['remitente']->getKey(), $f['conductor']->getKey()]) || $user->hasRole('admin') ? 403 : 404);
        }
        $this->assertNull($f['qr']->fresh()->utilizado_en);
        $this->assertSame(0, FirmaRecepcionEnvio::count());
        $this->assertSame([], Storage::disk('local')->allFiles());
    }

    public function test_solo_consulta_y_permiso_retirado_no_autorizan_confirmar(): void
    {
        $f = EnvioQrFixture::crear();
        \Spatie\Permission\Models\Role::findByName('jefe_planta', 'web')->revokePermissionTo('recepcion_planta.confirm');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();
        $this->actingAs($f['receptor'])->getJson('/api/envios/agricola/'.$f['envio']->getKey())->assertOk();
        $this->confirmar($f)->assertForbidden();
        $this->assertNull($f['qr']->fresh()->utilizado_en);
    }

    public function test_codigos_invalidos_url_ajena_y_envio_anidado_incorrecto_no_escriben(): void
    {
        $f = EnvioQrFixture::crear();
        $otro = EnvioQrFixture::crear();
        $antes = AlmacenMovimiento::count();
        foreach (['invalido', str_repeat('x', 48), $f['qr']->getRawOriginal('token'), 'https://ajeno.example/recepcion/'.$f['qr']->token, app(EnvioRecepcionQrService::class)->url($f['qr']).'?redirect=otro'] as $codigo) {
            $this->actingAs($f['receptor'])->postJson('/api/envios/qr/resolver', ['codigo' => $codigo])->assertUnprocessable();
        }
        $data = $this->payload($f);
        $data['codigo'] = $otro['qr']->token;
        $this->confirmar($f, $data)->assertNotFound();
        $this->assertSame($antes, AlmacenMovimiento::count());
        $this->assertNull($f['qr']->fresh()->utilizado_en);
    }

    public function test_lineas_ajenas_duplicadas_y_cantidades_invalidas_no_consumen_codigo(): void
    {
        $f = EnvioQrFixture::crear();
        foreach ([-1, 0, true, '1.0000001', '1e2', '11', [], null] as $valor) {
            $data = $this->payload($f);
            $data['lineas'][0]['cantidad_recibida'] = $valor;
            $this->confirmar($f, $data)->assertUnprocessable();
        }
        $data = $this->payload($f);
        $data['lineas'][] = $data['lineas'][0];
        $this->confirmar($f, $data)->assertUnprocessable();
        $data = $this->payload($f);
        $data['lineas'][0]['id'] = 999999;
        $this->confirmar($f, $data)->assertUnprocessable();
        $data = $this->payload($f);
        $data['lineas'][0]['factor'] = '100';
        $this->confirmar($f, $data)->assertUnprocessable();
        $data = $this->payload($f);
        $data['firmante_usuarioid'] = $f['conductor']->getKey();
        $this->confirmar($f, $data)->assertUnprocessable();
        $this->assertNull($f['qr']->fresh()->utilizado_en);
        $this->assertSame([], Storage::disk('local')->allFiles());
    }

    public function test_faltantes_respetan_reglas_existentes_y_distribucion_no_admite_parciales(): void
    {
        $f = EnvioQrFixture::crear();
        $data = $this->payload($f);
        $data['lineas'][0]['cantidad_recibida'] = '9.123456';
        $this->confirmar($f, $data)->assertCreated()->assertJsonPath('data.lineas.0.cantidad_recibida', '9.123456');
        $this->assertSame('9.123456', AlmacenMovimiento::first()->getRawOriginal('cantidad'));
        $f = EnvioQrFixture::crear('distribucion');
        $data = $this->payload($f);
        $data['lineas'][0]['cantidad_recibida'] = '4';
        $this->confirmar($f, $data)->assertUnprocessable();
        $f = EnvioQrFixture::crear('traslado');
        $data = $this->payload($f);
        $data['lineas'][0]['cantidad_recibida'] = '4';
        $this->confirmar($f, $data)->assertUnprocessable();
        $data['lineas'][0]['motivo'] = 'Faltante verificado';
        $this->confirmar($f, $data)->assertCreated()->assertJsonPath('data.lineas.0.motivo', 'Faltante verificado');
    }

    public function test_firma_ausente_vacia_truncada_y_excesiva_se_rechazan(): void
    {
        $f = EnvioQrFixture::crear();
        foreach (['', EnvioQrFixture::firma(true), 'data:image/png;base64,iVBORw0KGgo=', 'data:image/svg+xml;base64,'.base64_encode('<svg/>'), str_repeat('x', 1400001)] as $imagen) {
            $data = $this->payload($f);
            $data['imagen_firma'] = $imagen;
            $this->confirmar($f, $data)->assertUnprocessable();
        }
        $this->assertSame([], Storage::disk('local')->allFiles());
        $this->assertNull($f['qr']->fresh()->utilizado_en);
    }

    public function test_estado_incompatible_no_crea_firma_ni_movimientos(): void
    {
        $f = EnvioQrFixture::crear();
        $f['envio']->update(['estado' => 'cancelado']);
        $this->confirmar($f)->assertUnprocessable();
        $this->assertSame(0, AlmacenMovimiento::count());
        $this->assertNull($f['qr']->fresh()->utilizado_en);
    }

    public function test_fallo_de_bd_revierte_firma_stock_codigo_y_limpia_archivo(): void
    {
        $f = EnvioQrFixture::crear();
        AlmacenMovimiento::creating(fn () => throw new \RuntimeException('Fallo controlado QR'));
        $this->confirmar($f)->assertServerError();
        AlmacenMovimiento::flushEventListeners();
        $this->assertNull($f['qr']->fresh()->utilizado_en);
        $this->assertSame(0, AlmacenMovimiento::count());
        $this->assertSame(0, FirmaRecepcionEnvio::count());
        $this->assertNull($f['envio']->fresh()->fecha_recepcion_planta);
        $this->assertSame([], Storage::disk('local')->allFiles());
        $this->confirmar($f)->assertCreated();
    }

    public function test_fallo_de_almacenamiento_no_consume_codigo(): void
    {
        $f = EnvioQrFixture::crear();
        $mock = \Mockery::mock(\Illuminate\Filesystem\FilesystemAdapter::class);
        $mock->shouldReceive('put')->once()->andReturn(false);
        $mock->shouldReceive('delete')->once()->andReturn(true);
        Storage::shouldReceive('disk')->with('local')->andReturn($mock);
        $this->confirmar($f)->assertServerError();
        $this->assertNull($f['qr']->fresh()->utilizado_en);
        $this->assertSame(0, AlmacenMovimiento::count());
        $this->assertSame(0, FirmaRecepcionEnvio::count());
    }

    public function test_web_api_y_acceso_directo_a_comprobante_y_firma_aplican_mismo_ambito(): void
    {
        $f = EnvioQrFixture::crear();
        $this->actingAs($f['receptor'])->get(route('recepcion.publica', $f['qr']->token))->assertOk()->assertSee('10.123456')->assertSee('Confirmar recepción');
        $data = $this->payload($f);
        unset($data['codigo']);
        $this->post(route('recepcion.publica.firmar', $f['qr']->token), $data)->assertRedirect();
        $this->getJson('/api/recepciones-envio/'.$f['qr']->getKey())->assertOk()->assertJsonPath('data.lineas.0.cantidad_recibida', '10.123456');
        $this->get(route('recepcion.publica', $f['qr']->token))->assertSee('ya fue utilizado')->assertSee('Ver comprobante');
        $ajeno = CertificadosFixture::usuario('jefe_planta', 'no52');
        foreach (['', '/firma', '/comprobante'] as $sufijo) {
            $this->actingAs($ajeno)->getJson('/api/recepciones-envio/'.$f['qr']->getKey().$sufijo)->assertNotFound();
        }
        $this->get(route('recepcion.comprobante', $f['qr']->getKey()))->assertNotFound();
        $this->get(route('recepcion.publica', $f['qr']->token))->assertNotFound();
    }

    public function test_emision_por_destinatario_exige_cuenta_y_no_muta_para_un_remitente(): void
    {
        $f = EnvioQrFixture::crear('distribucion', true);
        $uri = '/api/envios/distribucion/'.$f['envio']->getKey().'/codigos';
        $this->postJson($uri)->assertUnauthorized();
        $this->actingAs($f['receptor'])->postJson($uri)->assertOk()->assertJsonCount(1, 'data');
        $this->actingAs($f['conductor'])->postJson($uri)->assertOk()->assertJsonCount(2, 'data');
        $antes = RecepcionQrEnvio::count();
        $this->actingAs($f['remitente'])->postJson($uri)->assertForbidden();
        $this->assertSame($antes, RecepcionQrEnvio::count());
    }

    public function test_detecta_duplicados_aun_con_el_numero_correcto_de_lineas_y_qr_legacy_redirige(): void
    {
        $f = EnvioQrFixture::crear();
        $d = $f['detalle']->replicate();
        $d->save();
        $data = $this->payload($f);
        $data['lineas'][1]['id'] = $data['lineas'][0]['id'];
        $this->confirmar($f, $data)->assertUnprocessable();
        $this->assertNull($f['qr']->fresh()->utilizado_en);
        // Enlace agrícola anterior: conserva su secreto, pero muestra la recepción con cantidades.
        $f['qr']->forceFill(['clave_operacion' => null])->save();
        $this->actingAs($f['receptor'])->get(route('recepcion.publica', $f['qr']->token))->assertRedirect(route('recepcion.publica', $f['qr']->token));
        $this->get(route('recepcion.publica', $f['qr']->token))->assertOk()->assertSee('10.123456');
    }

    public function test_error_al_generar_comprobante_no_revierte_recepcion_confirmada(): void
    {
        $f = EnvioQrFixture::crear();
        $this->confirmar($f)->assertCreated();
        \Barryvdh\DomPDF\Facade\Pdf::shouldReceive('loadView')->once()->andThrow(new \RuntimeException('PDF no disponible'));
        $this->getJson('/api/recepciones-envio/'.$f['qr']->getKey().'/comprobante')->assertServerError();
        $this->getJson('/api/recepciones-envio/'.$f['qr']->getKey())->assertOk();
        $this->assertNotNull($f['qr']->fresh()->utilizado_en);
        $this->assertSame(1, AlmacenMovimiento::count());
        Storage::disk('local')->assertExists($f['qr']->fresh()->firma_path);
    }

    public function test_recepcion_suma_saldo_previo_y_conserva_equivalencia_del_despacho(): void
    {
        $f = EnvioQrFixture::crear('distribucion');
        $almacen = app(\App\Services\PuntoVentaAlmacenService::class)->crearAlmacenParaPuntoVenta($f['pdv']);
        $producto = Insumo::create(['nombre' => $f['insumo']->nombre, 'almacenid' => $almacen->getKey(), 'tipoinsumoid' => $f['insumo']->tipoinsumoid,
            'unidadmedidaid' => $f['kg']->getKey(), 'stock' => '3.000000']);
        $f['presentacion']->update(['peso_neto_kg' => 7]);
        $this->confirmar($f)->assertCreated()->assertJsonPath('data.lineas.0.cantidad_recibida', '5.123456');
        $this->assertSame('13.246912', $producto->fresh()->getRawOriginal('stock'));
        $ingreso = AlmacenMovimiento::where('almacenid', $almacen->getKey())->firstOrFail();
        $this->assertSame('10.246912', $ingreso->getRawOriginal('cantidad'));
        $this->assertSame('5.123456', (string) \Brick\Math\BigDecimal::of($ingreso->getRawOriginal('cantidad_unidades'))->toScale(6));
        $f['insumo']->update(['nombre' => 'Nombre de catálogo posterior']);
        $this->getJson('/api/recepciones-envio/'.$f['qr']->getKey())->assertOk()->assertJsonPath('data.lineas.0.producto', 'Producto QR');
    }

    public function test_fallo_al_consumir_codigo_revierte_tambien_movimientos_ya_creados(): void
    {
        $f = EnvioQrFixture::crear();
        RecepcionQrEnvio::updating(function ($qr) {
            if ($qr->utilizado_en !== null) {
                throw new \RuntimeException('Fallo antes del commit de recepción');
            }
        });
        $this->confirmar($f)->assertServerError();
        RecepcionQrEnvio::flushEventListeners();
        $this->assertNull($f['qr']->fresh()->utilizado_en);
        $this->assertSame(0, AlmacenMovimiento::count());
        $this->assertSame(0, FirmaRecepcionEnvio::count());
        $this->assertNull($f['envio']->fresh()->fecha_recepcion_planta);
        $this->assertSame([], Storage::disk('local')->allFiles());
        $this->confirmar($f)->assertCreated();
    }

    public function test_guia_historica_publica_no_republica_la_firma_de_la_recepcion_privada(): void
    {
        $f = EnvioQrFixture::crear();
        $this->confirmar($f)->assertCreated();
        $documento = \App\Models\DocumentoEntrega::create(['externo_envio_id' => $f['envio']->externo_envio_id,
            'pedidoid' => $f['pedido']->getKey(), 'usuarioid' => $f['conductor']->getKey(), 'tipo_documento' => 'guia_transporte',
            'titulo' => 'Guía operativa', 'archivo_path' => 'documentos/guia-operativa.pdf',
            'metadata' => ['envio_cierre_agricola' => true, 'envioasignacionmultipleid' => $f['envio']->getKey()]]);
        $contexto = \App\Support\DocumentoEntregaArchivo::contextoPdf($documento);
        $this->assertNull($contexto['firmaRecepcionImg']);
        $this->get('/api/recepciones-envio/'.$f['qr']->getKey().'/firma')->assertOk()->assertHeader('Content-Type', 'image/png');
    }
}
