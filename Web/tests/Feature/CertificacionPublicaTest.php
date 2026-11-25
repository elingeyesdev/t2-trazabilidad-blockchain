<?php

namespace Tests\Feature;

use App\Models\CertificacionLote;
use App\Models\Cultivo;
use App\Models\EstadoLoteTipo;
use App\Models\EvaluacionFinalLoteProduccion;
use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Models\Pedido;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Services\CertificacionPublicaService;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class CertificacionPublicaTest extends TestCase
{
    use RefreshDatabase;

    private Usuario $usuario;

    private Lote $campo;

    private Lote $otroCampo;

    private LoteProduccionPedido $planta;

    protected function setUp(): void
    {
        parent::setUp();
        Http::preventStrayRequests();
        $this->usuario = Usuario::create(['nombre' => 'NOMBRE-PRIVADO-61', 'apellido' => 'APELLIDO-PRIVADO-61',
            'nombreusuario' => 'USUARIO-PRIVADO-61', 'email' => 'CORREO-PRIVADO-61@example.test',
            'passwordhash' => bcrypt('CLAVE-PRIVADA-61'), 'role' => 'jefe_agricultor', 'activo' => true]);
        $unidad = UnidadMedida::firstOrCreate(['abreviatura' => 'ha'], ['nombre' => 'Hectarea', 'categoria' => 'superficie']);
        $cultivo = Cultivo::firstOrCreate(['nombre' => 'Tomate']);
        $estado = EstadoLoteTipo::firstOrCreate(['nombre' => 'Disponible']);
        foreach (['campo' => 'TRZ-20261124-CAMPO61', 'otroCampo' => 'TRZ-20261124-AJENO61'] as $propiedad => $codigo) {
            $this->{$propiedad} = Lote::create(['usuarioid' => $this->usuario->getKey(), 'nombre' => 'Campo '.$propiedad,
                'ubicacion' => 'DOMICILIO-PRIVADO-61', 'superficie' => 1, 'unidadsuperficieid' => $unidad->getKey(),
                'cultivoid' => $cultivo->getKey(), 'estadolotetipoid' => $estado->getKey(), 'codigo_trazabilidad' => $codigo]);
        }
        $pedido = Pedido::create(['numero_solicitud' => 'PED-CERT61', 'estado' => 'pendiente', 'latitud' => -17.7, 'longitud' => -63.1]);
        $this->planta = LoteProduccionPedido::create(['pedidoid' => $pedido->getKey(), 'codigo_lote' => 'LP-CERT61',
            'nombre' => 'Produccion propia', 'producto' => 'Tomate', 'fecha_creacion' => '2026-11-24']);
    }

    private function emitir(string $codigo, array $extra = [], ?Lote $campo = null): CertificacionLote
    {
        $emision = new CertificacionLote;
        $emision->forceFill([
            'loteid' => ($campo ?? $this->campo)->getKey(), 'usuarioid' => $this->usuario->getKey(),
            'codigo_certificado' => $codigo, 'resultado' => 'Certificado', 'fecha_certificacion' => '2026-11-24 10:00:00',
            'observaciones' => 'NOTA-PRIVADA-61', 'recomendaciones' => 'RECOMENDACION-PRIVADA-61',
            'archivo_path' => 'certificados/ARCHIVO-PRIVADO-61.pdf', 'solicitud_huella' => str_repeat('d', 64),
            'datos_emision' => ['emision' => ['emisor' => 'EMISOR-PRIVADO-61'],
                'blockchain_base' => ['credencial' => 'RPC-SECRETO-61'], 'firma' => 'FIRMA-PRIVADA-61'],
            'blockchain_error' => 'ERROR-PRIVADO-61', 'blockchain_operacion_id' => 'OPERACION-PRIVADA-61',
            'blockchain_solicitud_id' => 'SOLICITUD-PRIVADA-61', ...$extra,
        ])->save();

        return $emision->fresh();
    }

    public function test_historial_con_fks_es_publico_ordenado_y_no_mezcla_otro_lote(): void
    {
        $a = $this->emitir('CERT-CAMPO61-A', ['fecha_certificacion' => '2026-11-23 09:00:00']);
        $b = $this->emitir('NCONF-CAMPO61-B', ['resultado' => 'No conforme']);
        $this->emitir('CERT-AJENO61', [], $this->otroCampo);
        $planta = new EvaluacionFinalLoteProduccion;
        $planta->forceFill(['loteproduccionpedidoid' => $this->planta->getKey(), 'inspector_usuarioid' => $this->usuario->getKey(),
            'codigo_certificado' => 'PLANTA-CERT61', 'razon' => 'Certificado', 'fecha_evaluacion' => '2026-11-24 11:00:00',
            'observaciones' => 'NOTA-PLANTA-PRIVADA-61', 'archivo_path' => 'certificados/PLANTA-PRIVADA-61.pdf'])->save();

        $r = app(CertificacionPublicaService::class)->proyectar(collect([$this->campo, $this->campo]), collect([$this->planta]));
        $this->assertSame('con_emisiones_registradas', $r['certificaciones']['estado']);
        $this->assertSame(['CERT-CAMPO61-A', 'NCONF-CAMPO61-B', 'PLANTA-CERT61'], array_column($r['certificaciones']['emisiones'], 'codigo_certificado'));
        $this->assertSame(['Certificado', 'No conforme', 'Certificado'], array_column($r['certificaciones']['emisiones'], 'resultado'));
        $this->assertSame(['no_determinada'], array_values(array_unique(array_column($r['certificaciones']['emisiones'], 'vigencia'))));
        $this->assertSame(['TRZ-20261124-CAMPO61', 'TRZ-20261124-CAMPO61', 'LP-CERT61'], array_column($r['certificaciones']['emisiones'], 'codigo_lote'));
        $this->assertSame('sin_respaldo_registrado', $r['blockchain']['estado']);
        $json = json_encode($r, JSON_THROW_ON_ERROR);
        foreach (['PRIVADO-61', 'PRIVADA-61', 'RPC-SECRETO-61', 'CERT-AJENO61', $this->usuario->passwordhash] as $secreto) {
            $this->assertStringNotContainsString($secreto, $json);
        }
        $this->assertSame($a->getAttributes(), $a->fresh()->getAttributes());
        $this->assertSame($b->getAttributes(), $b->fresh()->getAttributes());
        Http::assertNothingSent();
    }

    public function test_estados_blockchain_son_registros_locales_y_un_hash_no_confirma(): void
    {
        foreach (['pendiente', 'certificada', 'rechazada', 'error', 'omitida', 'confirmado'] as $i => $estado) {
            $this->emitir('CERT-BC61-'.$i, ['blockchain_estado' => $estado, 'blockchain_hash' => str_repeat('a', 64),
                'blockchain_txid' => in_array($estado, ['certificada', 'confirmado'], true) ? 'tx-publica-'.$i : null,
                'blockchain_enviado_en' => '2026-11-24 10:01:00',
                'blockchain_certificado_en' => $estado === 'certificada' ? '2026-11-24 10:02:00' : null]);
        }
        $this->emitir('CERT-HASH-SOLO61', ['blockchain_hash' => str_repeat('b', 64)]);
        $this->emitir('CERT-ESTADO-SIN-TX61', ['blockchain_estado' => 'certificada', 'blockchain_hash' => str_repeat('c', 64)]);
        $r = app(CertificacionPublicaService::class)->proyectar(collect([$this->campo]), collect());
        $this->assertSame('con_registros', $r['blockchain']['estado']);
        $this->assertCount(8, $r['blockchain']['registros']);
        $registros = collect($r['blockchain']['registros'])->keyBy('codigo_certificado');
        foreach (['pendiente', 'certificada', 'rechazada', 'error', 'omitida', 'confirmado'] as $i => $estado) {
            $registro = $registros['CERT-BC61-'.$i];
            $this->assertSame($estado, $registro['estado_registrado']);
            $this->assertSame(in_array($estado, ['certificada', 'confirmado'], true), $registro['confirmacion_registrada']);
            $this->assertSame('registro_local', $registro['fuente']);
            $this->assertFalse($registro['verificado_en_vivo']);
            foreach (['hash_documento', 'hash_bloque', 'red', 'explorador_url', 'ultima_comprobacion_en'] as $ausente) {
                $this->assertNull($registro[$ausente]);
            }
        }
        $this->assertFalse($registros['CERT-HASH-SOLO61']['confirmacion_registrada']);
        $this->assertFalse($registros['CERT-ESTADO-SIN-TX61']['confirmacion_registrada']);
        $this->assertSame(str_repeat('b', 64), $registros['CERT-HASH-SOLO61']['hash_payload']);
        $json = json_encode($r, JSON_THROW_ON_ERROR);
        foreach (['ERROR-PRIVADO-61', 'OPERACION-PRIVADA-61', 'SOLICITUD-PRIVADA-61', 'RPC-SECRETO-61'] as $secreto) {
            $this->assertStringNotContainsString($secreto, $json);
        }
        Http::assertNothingSent();
    }

    public function test_sin_emisiones_y_consultas_repetidas_sin_escritura_o_proveedor(): void
    {
        $this->emitir('CERT-NO-VINCULADO61', [], $this->otroCampo);
        DB::flushQueryLog();
        DB::enableQueryLog();
        $service = app(CertificacionPublicaService::class);
        $a = $service->proyectar(collect([$this->campo]), collect([$this->planta]));
        $b = $service->proyectar(collect([$this->campo]), collect([$this->planta]));
        $consultas = DB::getQueryLog();
        DB::disableQueryLog();
        $this->assertSame($a, $b);
        $this->assertSame(['certificaciones' => ['estado' => 'sin_certificacion_registrada', 'emisiones' => []],
            'blockchain' => ['estado' => 'sin_respaldo_registrado', 'registros' => []]], $a);
        $this->assertCount(2, $consultas);
        foreach ($consultas as $consulta) {
            $this->assertMatchesRegularExpression('/^select\b/i', $consulta['query']);
        }
        $this->assertDatabaseCount('certificacion_lote', 1);
        $this->assertDatabaseCount('evaluacion_final_lote_produccion', 0);
        Http::assertNothingSent();
    }

    public function test_revalida_fk_de_relacion_precargada_sin_duplicar_emisiones(): void
    {
        $propia = $this->emitir('CERT-PROPIA61');
        $ajena = $this->emitir('CERT-RELACION-AJENA61', [], $this->otroCampo);
        $this->campo->setRelation('certificaciones', new EloquentCollection([$propia, $propia, $ajena]));
        $r = app(CertificacionPublicaService::class)->proyectar(collect([$this->campo]), collect());
        $this->assertSame(['CERT-PROPIA61'], array_column($r['certificaciones']['emisiones'], 'codigo_certificado'));
        Http::assertNothingSent();
    }

    public function test_textos_legacy_de_evaluacion_o_estado_no_sustituyen_resultados_publicos(): void
    {
        $this->emitir('CERT-LEGACY61', ['resultado' => 'MOTIVO-LEGACY-PRIVADO-61', 'blockchain_estado' => 'ESTADO-LEGACY-PRIVADO-61']);
        $planta = new EvaluacionFinalLoteProduccion;
        $planta->forceFill(['loteproduccionpedidoid' => $this->planta->getKey(), 'codigo_certificado' => 'PLANTA-LEGACY61',
            'razon' => 'RAZON-LEGACY-PRIVADA-61', 'fecha_evaluacion' => '2026-11-24 11:00:00'])->save();
        $r = app(CertificacionPublicaService::class)->proyectar(collect([$this->campo]), collect([$this->planta]));
        $this->assertSame([null, null], array_column($r['certificaciones']['emisiones'], 'resultado'));
        $this->assertNull($r['blockchain']['registros'][0]['estado_registrado']);
        $this->assertStringNotContainsString('LEGACY-PRIVAD', json_encode($r, JSON_THROW_ON_ERROR));
        Http::assertNothingSent();
    }
}
