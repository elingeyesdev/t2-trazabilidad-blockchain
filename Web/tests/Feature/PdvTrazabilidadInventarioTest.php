<?php

namespace Tests\Feature;

use App\Models\Almacen;
use App\Models\Insumo;
use App\Models\PuntoVenta;
use App\Models\TipoAlmacen;
use App\Models\TipoInsumo;
use App\Models\UnidadMedida;
use App\Support\CodigoTrazabilidadPdv;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\CertificadosFixture;
use Tests\TestCase;

class PdvTrazabilidadInventarioTest extends TestCase
{
    use RefreshDatabase;

    private $dueno;

    private Almacen $almacen;

    private Insumo $producto;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        config(['app.url' => 'https://agrofusion.example.test', 'app.public_url' => null]);
        $this->dueno = CertificadosFixture::usuario('minorista', 'minorista63');
        $this->almacen = $this->crearAlmacen($this->dueno, 'Tienda A');
        $this->producto = $this->crearProducto($this->almacen);
    }

    private function crearAlmacen($dueno, string $nombre): Almacen
    {
        $kg = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
        $almacen = Almacen::create(['nombre' => $nombre, 'ambito' => 'punto_venta', 'ubicacion' => 'DIRECCION-PRIVADA-63',
            'activo' => true, 'unidadmedidaid' => $kg->getKey(), 'capacidad' => 1000,
            'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Punto de venta'])->getKey()]);
        PuntoVenta::create(['nombre' => $nombre, 'usuarioid' => $dueno->getKey(), 'almacenid' => $almacen->getKey(), 'activo' => true]);

        return $almacen;
    }

    private function crearProducto(Almacen $almacen): Insumo
    {
        return Insumo::create(['nombre' => 'Mismo producto', 'almacenid' => $almacen->getKey(), 'stock' => '12.123456',
            'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Producto terminado'])->getKey(),
            'unidadmedidaid' => $almacen->unidadmedidaid]);
    }

    private function autenticar($usuario): void
    {
        app('auth')->forgetGuards();
        $this->withHeaders(['Authorization' => 'Bearer '.$usuario->createToken('edt63')->plainTextToken]);
    }

    public function test_producto_nuevo_codigo_persistente_y_api_listado_detalle_url_del_entorno(): void
    {
        $codigo = $this->producto->codigo_trazabilidad;
        $this->assertMatchesRegularExpression('/^TRZ-PDV-[A-F0-9-]{36}$/', $codigo);
        $this->autenticar($this->dueno);
        $url = 'https://agrofusion.example.test/trazabilidad/'.$codigo;
        $this->getJson('/api/punto-venta/inventario')->assertOk()->assertJsonPath('0.codigo_trazabilidad', $codigo)
            ->assertJsonPath('0.trazabilidad_url', $url)->assertJsonPath('0.trazabilidad_estado', 'disponible');
        $this->getJson('/api/punto-venta/inventario/'.$this->producto->getKey())->assertOk()
            ->assertJsonPath('codigo_trazabilidad', $codigo)->assertJsonPath('trazabilidad_url', $url);
        $this->getJson('/api/punto-venta/inventario/'.$this->producto->getKey())->assertOk();
        $this->assertSame($codigo, $this->producto->fresh()->codigo_trazabilidad);
        $this->get('/trazabilidad/'.$codigo)->assertOk()->assertViewHas('reporte.codigo', $codigo);
        $this->getJson('/api/trazabilidad/'.$codigo)->assertOk()->assertJsonPath('producto.codigo', $codigo);
        $this->autenticar(CertificadosFixture::usuario('admin', 'supervisor63'));
        $this->getJson('/api/insumos/'.$this->producto->getKey())->assertOk()->assertJsonPath('trazabilidad_url', $url);
        $this->getJson('/api/insumos')->assertOk()->assertJsonFragment(['codigo_trazabilidad' => $codigo, 'trazabilidad_url' => $url]);
    }

    public function test_propietario_no_ve_otro_pdv_ni_se_mezclan_por_nombre(): void
    {
        $otro = CertificadosFixture::usuario('minorista', 'minoristaAjeno63');
        $productoAjeno = $this->crearProducto($this->crearAlmacen($otro, 'Tienda B'));
        $this->assertNotSame($this->producto->codigo_trazabilidad, $productoAjeno->codigo_trazabilidad);
        $this->autenticar($this->dueno);
        $this->getJson('/api/punto-venta/inventario')->assertOk()->assertJsonCount(1)
            ->assertDontSee($productoAjeno->codigo_trazabilidad);
        $this->getJson('/api/punto-venta/inventario/'.$productoAjeno->getKey())->assertNotFound();
        $this->getJson('/api/trazabilidad/'.$this->producto->codigo_trazabilidad)->assertOk()->assertDontSee($productoAjeno->codigo_trazabilidad);
        $this->getJson('/api/insumos')->assertForbidden();
        $this->postJson('/api/insumos', ['nombre' => 'No autorizado'])->assertForbidden();
    }

    public function test_gets_no_regularizan_ni_cambian_cantidades_y_distinguen_no_aplica(): void
    {
        DB::table('insumo')->where('insumoid', $this->producto->getKey())->update(['codigo_trazabilidad' => null]);
        $catalogo = Insumo::create(['nombre' => 'Semilla de catálogo', 'stock' => 2, 'tipoinsumoid' => $this->producto->tipoinsumoid, 'unidadmedidaid' => $this->producto->unidadmedidaid]);
        $this->autenticar($this->dueno);
        $writes = [];
        DB::listen(function (QueryExecuted $q) use (&$writes) {
            // Sanctum legitimately audits token usage; inventory/public-code GETs must not write business data.
            if (preg_match('/^\s*(insert|update|delete|replace)\b/i', $q->sql) && ! str_contains($q->sql, 'personal_access_tokens')) {
                $writes[] = $q->sql;
            }
        });
        $this->getJson('/api/punto-venta/inventario/'.$this->producto->getKey())->assertOk()
            ->assertJsonPath('codigo_trazabilidad', null)->assertJsonPath('trazabilidad_url', null)->assertJsonPath('trazabilidad_estado', 'sin_codigo_todavia');
        $this->getJson('/api/punto-venta/inventario')->assertOk();
        $this->assertSame([], $writes);
        $this->assertNull($this->producto->fresh()->codigo_trazabilidad);
        $this->assertSame('12.123456', (string) $this->producto->fresh()->getRawOriginal('stock'));
        $this->assertSame('no_aplica', CodigoTrazabilidadPdv::datos($catalogo)['trazabilidad_estado']);
    }

    public function test_regularizacion_controlada_repetible_y_codigo_existente_no_se_sobrescribe(): void
    {
        $existente = $this->producto->codigo_trazabilidad;
        $viejo = $this->crearProducto($this->almacen);
        DB::table('insumo')->where('insumoid', $viejo->getKey())->update(['codigo_trazabilidad' => null]);
        $catalogo = Insumo::create(['nombre' => 'No PDV', 'stock' => 1, 'tipoinsumoid' => $viejo->tipoinsumoid, 'unidadmedidaid' => $viejo->unidadmedidaid]);
        $this->artisan('trazabilidad:regularizar-pdv')->assertSuccessful();
        $this->assertNull($viejo->fresh()->codigo_trazabilidad);
        $this->artisan('trazabilidad:regularizar-pdv', ['--aplicar' => true])->assertSuccessful();
        $codigo = $viejo->fresh()->codigo_trazabilidad;
        $this->assertNotNull($codigo);
        $this->artisan('trazabilidad:regularizar-pdv', ['--aplicar' => true])->assertSuccessful();
        $this->assertSame($codigo, $viejo->fresh()->codigo_trazabilidad);
        $this->assertSame($existente, $this->producto->fresh()->codigo_trazabilidad);
        $this->assertNull($catalogo->fresh()->codigo_trazabilidad);
        $this->getJson('/api/trazabilidad/'.$codigo)->assertOk()->assertJsonPath('codigo', $codigo);
        $viejo->update(['codigo_trazabilidad' => 'LEGACY-PDV-NO-REEMPLAZAR']);
        $this->artisan('trazabilidad:regularizar-pdv', ['--aplicar' => true])->assertSuccessful();
        $this->assertSame('LEGACY-PDV-NO-REEMPLAZAR', $viejo->fresh()->codigo_trazabilidad);
        $this->assertNull(CodigoTrazabilidadPdv::datos($viejo->fresh())['trazabilidad_url']);
    }

    public function test_regularizaciones_con_modelos_obsoletos_preservan_ganador_y_bd_impide_duplicados(): void
    {
        DB::table('insumo')->where('insumoid', $this->producto->getKey())->update(['codigo_trazabilidad' => null]);
        $a = $this->producto->fresh();
        $b = $this->producto->fresh();
        $codigo = CodigoTrazabilidadPdv::asegurar($a);
        $this->assertSame($codigo, CodigoTrazabilidadPdv::asegurar($b));
        $duplicado = $this->producto->replicate();
        $duplicado->codigo_trazabilidad = $codigo;
        $this->expectException(QueryException::class);
        $duplicado->save();
    }
}
