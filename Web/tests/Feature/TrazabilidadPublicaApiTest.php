<?php

namespace Tests\Feature;

use App\Models\FirmaTransportistaEnvio;
use App\Models\IncidenteEnvio;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Services\EnvioRecepcionQrService;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\Support\CertificadosFixture;
use Tests\Support\TrazabilidadPublicaFixture;
use Tests\TestCase;

class TrazabilidadPublicaApiTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    protected function setUp(): void
    {
        parent::setUp();
        $this->f = TrazabilidadPublicaFixture::crear();
        $this->withServerVariables(['REMOTE_ADDR' => '198.51.100.61']);
    }

    private function url(string $codigo): string
    {
        return '/api/trazabilidad/'.rawurlencode($codigo);
    }

    public function test_lote_y_producto_pdv_se_consultan_sin_sesion_token_ni_accept_json(): void
    {
        foreach ([[$this->f['lote'], 'lote_agricola'], [$this->f['pdv'], 'pdv']] as [$modelo, $tipo]) {
            $this->get($this->url($modelo->codigo_trazabilidad))->assertOk()
                ->assertHeader('content-type', 'application/json')
                ->assertJsonPath('codigo', $modelo->codigo_trazabilidad)
                ->assertJsonPath('tipo', $tipo)
                ->assertJsonPath('producto.codigo', $modelo->codigo_trazabilidad)
                ->assertJsonStructure([
                    'codigo', 'tipo', 'producto' => ['codigo', 'nombre'], 'origenes',
                    'etapas' => [['tipo', 'estado', 'eventos']], 'rutas', 'evidencias',
                    'certificaciones' => ['estado', 'emisiones'], 'blockchain' => ['estado', 'registros'],
                ]);
        }
        $this->assertGuest();
    }

    public function test_normaliza_exteriores_y_mayusculas_con_coincidencia_exacta(): void
    {
        $codigo = $this->f['lote']->codigo_trazabilidad;
        $this->get($this->url('  '.strtolower($codigo).'  '))->assertOk()->assertJsonPath('codigo', $codigo);
        $this->get($this->url('TRAZ-20261124-ABC124'))->assertNotFound();
        $this->get($this->url(substr($codigo, 0, -1)))->assertUnprocessable();
        $this->get($this->url($codigo.'X'))->assertUnprocessable();
    }

    public function test_formatos_historicos_agricola_y_uuid_pdv_son_compatibles(): void
    {
        $this->f['lote']->update(['codigo_trazabilidad' => 'TRZ-20261124-A1B2C3']);
        $this->get($this->url('trz-20261124-a1b2c3'))->assertOk()->assertJsonPath('tipo', 'lote_agricola');
        $codigo = 'TRZ-PDV-0519F897-301D-4ED2-A09A-A428B3DB5FC4';
        $this->f['pdv']->update(['codigo_trazabilidad' => strtolower($codigo)]);
        $this->get($this->url(strtolower($codigo)))->assertOk()->assertJsonPath('codigo', $codigo)->assertJsonPath('tipo', 'pdv');
    }

    public function test_prefijo_pdv_se_resuelve_antes_que_un_lote_con_el_mismo_codigo(): void
    {
        $codigo = $this->f['pdv']->codigo_trazabilidad;
        $this->f['lote']->update(['codigo_trazabilidad' => $codigo]);
        $this->get($this->url($codigo))->assertOk()->assertJsonPath('tipo', 'pdv')
            ->assertJsonPath('producto.nombre', $this->f['pdv']->nombre);
    }

    public function test_inexistente_es_json_descriptivo_y_no_coincide_parcialmente(): void
    {
        $this->get($this->url('TRAZ-20261124-ZZZ999'))->assertNotFound()
            ->assertHeader('content-type', 'application/json')->assertJsonStructure(['message']);
        $this->f['lote']->update(['codigo_trazabilidad' => 'TRAZ-20261124-ABC123-SUFIJO']);
        $this->get($this->url('TRAZ-20261124-ABC123'))->assertNotFound();
    }

    public function test_codigos_malformados_y_largos_devuelven_422_json_sin_accept(): void
    {
        foreach (['INVALIDO', 'TRAZ-20261124-ABC%23', 'TRAZ-20261124-AB C12', 'TRZ-MAY-20261124-ABC123',
            'https:example.test?token=NO-SOLICITAR-61', str_repeat('A', 81)] as $codigo) {
            $this->get($this->url($codigo))->assertUnprocessable()
                ->assertHeader('content-type', 'application/json')->assertJsonValidationErrors('codigo');
        }
    }

    public function test_duplicados_normalizados_son_ambiguos_y_no_se_elige_el_primero(): void
    {
        $duplicado = $this->f['lote']->replicate();
        $duplicado->codigo_trazabilidad = strtolower($this->f['lote']->codigo_trazabilidad);
        $duplicado->nombre = 'NO-ELEGIR-ARBITRARIAMENTE-61';
        $duplicado->save();
        $this->get($this->url($this->f['lote']->codigo_trazabilidad))->assertConflict()
            ->assertHeader('content-type', 'application/json')->assertJsonStructure(['message'])
            ->assertDontSee('NO-ELEGIR-ARBITRARIAMENTE-61');
    }

    public function test_etapas_ordenadas_y_ausencias_explicitas_sin_inventar_operaciones(): void
    {
        $respuesta = $this->get($this->url($this->f['pdv']->codigo_trazabilidad))->assertOk();
        $etapas = $respuesta->json('etapas');
        $this->assertSame(['agricola', 'planta', 'mayorista', 'distribucion', 'pdv'], array_column($etapas, 'tipo'));
        foreach (array_slice($etapas, 0, 4) as $etapa) {
            $this->assertSame([], $etapa['eventos']);
            $this->assertSame('sin_informacion_registrada', $etapa['estado']);
        }
        $this->assertSame([], $respuesta->json('rutas'));
        $this->assertSame([], $respuesta->json('evidencias'));
        $this->assertSame([], $respuesta->json('certificaciones.emisiones'));
        $this->assertSame([], $respuesta->json('blockchain.registros'));
    }

    public function test_proyeccion_explicita_no_expone_personas_notas_ubicaciones_ni_archivos_privados(): void
    {
        foreach ([$this->f['lote']->codigo_trazabilidad, $this->f['pdv']->codigo_trazabilidad] as $codigo) {
            $respuesta = $this->get($this->url($codigo))->assertOk();
            $json = $respuesta->getContent();
            foreach (['IDENTIDAD-PRIVADA-61', 'privado61@example.test', 'TEL-PRIVADO-61', 'HASH-PRIVADO-61',
                'NOTA-USUARIO-PRIVADA-61', 'DOMICILIO-PRIVADO-61', '-17.123456', '-63.987654',
                'FOTO-PRIVADA-61', 'PROVEEDOR-PRIVADO-61', 'NOTA-INTERNA-61', 'FOTO-PDV-PRIVADA-61'] as $privado) {
                $this->assertStringNotContainsString($privado, $json);
            }
            $this->assertSinClavesPrivadas($respuesta->json());
        }
    }

    public function test_pdv_conserva_dos_origenes_reales_precision_y_eventos_sin_mezclar_partidas_del_catalogo(): void
    {
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $real = CertificadosFixture::crear();
        $qr = app(EnvioRecepcionQrService::class)->emitir($real['envio'])[0];
        $qr->forceFill([
            'firma_path' => 'private/recepciones/FIRMA-RECEPCION-PRIVADA-61.png',
            'datos_recepcion' => ['firmante' => ['id' => $real['planta']->getKey(), 'nombre' => 'FIRMANTE-PRIVADO-61']],
        ])->save();
        FirmaTransportistaEnvio::create([
            'envioasignacionmultipleid' => $real['envio']->getKey(), 'imagenfirma' => 'FIRMA-TRANSPORTISTA-PRIVADA-61',
            'nombrefirmante' => 'TRANSPORTISTA-PRIVADO-61', 'fechafirma' => now(),
        ]);
        IncidenteEnvio::create([
            'afectado_tipo' => 'envio_agricola', 'envioasignacionmultipleid' => $real['envio']->getKey(),
            'reportadopor_usuarioid' => $real['agricola']->getKey(), 'tipo' => 'general',
            'descripcion' => 'INCIDENCIA-PRIVADA-61', 'estado' => 'resuelto', 'nota_resolucion' => 'SOLUCION-PRIVADA-61',
        ]);
        foreach ($real['campos'] as $i => $campo) {
            $campo->update(['codigo_trazabilidad' => 'TRAZ-20261124-ORIG0'.$i]);
            $campo->actividades()->update([
                'observaciones' => 'OBSERVACION-PRIVADA-61',
                'descripcion' => 'DESCRIPCION-INTERNA-61',
                'evidencia_foto_path' => 'private/FOTO-ACTIVIDAD-61.jpg',
                'detalle_json' => json_encode(['cierre' => ['resultado' => 'RESULTADO-PRIVADO-61']]),
            ]);
        }
        $this->f['pdv']->update(['almacenid' => $real['almacen']->getKey()]);
        $presentacion = InsumoPresentacion::create([
            'insumoid' => $this->f['pdv']->getKey(), 'nombre' => 'Bolsa 1 kg', 'peso_neto_kg' => 1,
            'tipo_envase' => 'bolsa', 'activo' => true,
        ]);
        $partida = InventarioPresentacionLote::create([
            'insumoid' => $this->f['pdv']->getKey(), 'almacenid' => $real['almacen']->getKey(),
            'insumo_presentacionid' => $presentacion->getKey(), 'loteproduccionpedidoid' => $real['lote']->getKey(),
            'cantidad_unidades' => '2.123456', 'cantidad_kg' => '2.123456',
        ]);
        $otroProceso = $real['lote']->replicate();
        $otroProceso->codigo_lote = 'PARTIDA-AJENA-61';
        $otroProceso->save();
        $otroProducto = $this->f['pdv']->replicate();
        $otroProducto->codigo_trazabilidad = 'TRZ-PDV-20261124-OTR123';
        $otroProducto->save();
        $otraPartida = $partida->replicate();
        $otraPartida->fill(['insumoid' => $otroProducto->getKey(), 'loteproduccionpedidoid' => $otroProceso->getKey()])->save();
        $otraCosecha = $real['campos'][0]->producciones()->first()->replicate();
        $otraCosecha->cantidad = '999.000000';
        $otraCosecha->cantidad_base = '999.000000';
        $otraCosecha->save();

        $respuesta = $this->get($this->url($this->f['pdv']->codigo_trazabilidad))->assertOk()->assertJsonCount(2, 'origenes');
        $this->assertSame(['TRAZ-20261124-ORIG00', 'TRAZ-20261124-ORIG01'], array_column($respuesta->json('origenes'), 'codigo'));
        $etapas = collect($respuesta->json('etapas'))->keyBy('tipo');
        $consumos = collect($etapas['planta']['eventos'])->where('tipo', 'consumo_registrado');
        $this->assertCount(2, $consumos);
        $this->assertSame(['5.123000'], $consumos->pluck('cantidad_consumida')->unique()->values()->all());
        $cosechas = collect($etapas['agricola']['eventos'])->where('tipo', 'cosecha');
        $this->assertCount(2, $cosechas);
        $this->assertSame(['100.123456'], $cosechas->pluck('cantidad')->unique()->values()->all());
        $this->assertCount(10, collect($etapas['agricola']['eventos'])->where('tipo', 'actividad_lote_origen'));
        $this->assertCount(1, collect($etapas['planta']['eventos'])->where('tipo', 'etapa_registrada'));
        foreach ($etapas as $etapa) {
            $orden = array_map(fn ($e) => [$e['fecha'] ?? '9999', $e['referencia']], $etapa['eventos']);
            $esperado = $orden;
            usort($esperado, fn ($a, $b) => $a <=> $b);
            $this->assertSame($esperado, $orden);
            $referencias = array_column($etapa['eventos'], 'referencia');
            $this->assertSame($referencias, array_values(array_unique($referencias)));
        }
        foreach (['PARTIDA-AJENA-61', '999.000000', 'OBSERVACION-PRIVADA-61', 'DESCRIPCION-INTERNA-61',
            'FOTO-ACTIVIDAD-61', 'RESULTADO-PRIVADO-61', $real['agricola']->email, $real['planta']->email,
            'FIRMA-RECEPCION-PRIVADA-61', 'FIRMANTE-PRIVADO-61', 'FIRMA-TRANSPORTISTA-PRIVADA-61',
            'TRANSPORTISTA-PRIVADO-61', 'INCIDENCIA-PRIVADA-61', 'SOLUCION-PRIVADA-61',
            $qr->token, $qr->getRawOriginal('token'), $qr->getRawOriginal('token_cifrado')] as $privado) {
            $this->assertStringNotContainsString($privado, $respuesta->getContent());
        }
        $this->assertSame([], $respuesta->json('evidencias'));
        $this->assertSinClavesPrivadas($respuesta->json());
    }

    private function assertSinClavesPrivadas(array $datos): void
    {
        $privadas = ['email', 'telefono', 'password', 'passwordhash', 'token', 'usuarioid', 'responsable_usuarioid',
            'latitud', 'longitud', 'direccion', 'direccion_texto', 'observaciones', 'imagenfirma', 'firma',
            'archivo_path', 'firma_path', 'qr_token', 'recepcion_token', 'private_key', 'rpc_url', 'datos_emision'];
        foreach ($datos as $clave => $valor) {
            $this->assertNotContains($clave, $privadas);
            if (is_array($valor)) {
                $this->assertSinClavesPrivadas($valor);
            }
        }
    }

    public function test_consultar_no_escribe_ni_emite_certificados_movimientos_o_registros_blockchain(): void
    {
        $tablas = Schema::getTableListing();
        $snapshot = fn () => collect($tablas)->mapWithKeys(fn ($tabla) => [$tabla => DB::table($tabla)->get()->map(fn ($fila) => (array) $fila)->all()])->all();
        $antes = $snapshot();
        $escrituras = [];
        DB::listen(function (QueryExecuted $consulta) use (&$escrituras): void {
            if (preg_match('/\A\s*(insert|update|delete|replace|alter|create|drop|truncate)\b/i', $consulta->sql)) {
                $escrituras[] = $consulta->sql;
            }
        });
        foreach ([$this->f['lote']->codigo_trazabilidad, $this->f['pdv']->codigo_trazabilidad] as $codigo) {
            $this->get($this->url($codigo))->assertOk();
        }
        $this->assertSame([], $escrituras, 'La consulta pública debe ser de solo lectura.');
        $this->assertSame($antes, $snapshot());
    }

    public function test_limitador_devuelve_429_json_y_forwarded_for_no_permita_evitarlo(): void
    {
        $url = $this->url($this->f['lote']->codigo_trazabilidad);
        for ($i = 1; $i <= 60; $i++) {
            $this->withHeader('X-Forwarded-For', '203.0.113.'.$i)->get($url)->assertOk();
        }
        $this->withHeader('X-Forwarded-For', '203.0.113.250')->get($url)->assertStatus(429)
            ->assertHeader('content-type', 'application/json')->assertJsonStructure(['message']);
    }

    public function test_endpoints_privados_conservan_autenticacion(): void
    {
        $this->getJson('/api/consulta-recorrido')->assertUnauthorized();
        $this->getJson('/api/envios/agricola/1')->assertUnauthorized();
        $this->assertGuest();
    }
}
