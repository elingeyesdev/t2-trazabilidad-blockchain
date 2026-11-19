<?php

namespace Tests\Feature;

use App\Models\AlmacenMovimiento;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Blade;
use Tests\Support\CertificadosFixture;
use Tests\TestCase;

class PantallasOperativasTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $this->f = CertificadosFixture::crear();
    }

    public function test_existencias_y_detalle_muestran_decimales_unidad_y_estados_sin_modificar_saldos(): void
    {
        $insumo = $this->f['lote']->materiasPrimas()->first()->insumo;
        $antes = $insumo->fresh()->getAttributes();
        $movimientos = AlmacenMovimiento::count();
        $this->actingAs($this->f['planta'])
            ->get(route('almacen-planta.existencias.index', $this->f['almacen']))->assertOk()
            ->assertSee('95.000456')->assertSee('kg')->assertSee('Sin fecha registrada')->assertSee('Guardar mínimo');
        $this->get(route('almacen-planta.inventario.show', [$this->f['almacen'], $insumo]))->assertOk()
            ->assertSee('95.000456')->assertSee('kg')->assertSee('Registrar ingreso');
        $this->assertSame($antes, $insumo->fresh()->getAttributes());
        $this->assertSame($movimientos, AlmacenMovimiento::count());
    }

    public function test_administrador_consulta_sin_enlaces_a_operaciones_ni_formularios_de_escritura(): void
    {
        $admin = CertificadosFixture::usuario('admin', 'admin45');
        $insumo = $this->f['lote']->materiasPrimas()->first()->insumo;
        $this->actingAs($admin)->get(route('almacen-planta.inventario.show', [$this->f['almacen'], $insumo]))->assertOk()
            ->assertDontSee('Registrar ingreso')->assertDontSee('Registrar salida')->assertDontSee('Editar producto');
        $this->get(route('almacen-planta.existencias.index', $this->f['almacen']))->assertOk()->assertDontSee('Guardar mínimo');
        $this->patch(route('almacen-planta.existencias.minimo', [$this->f['almacen'], $insumo]), ['stockminimo' => 5])->assertForbidden();
    }

    public function test_planta_muestra_materias_con_su_unidad_y_no_ofrece_eliminar_lotes_procesados(): void
    {
        $this->actingAs($this->f['planta'])->get(route('procesamiento.index'))->assertOk()
            ->assertSee('5.123')->assertSee('10.246')->assertSee('kg')->assertSee('Nuevo lote')
            ->assertDontSee('action="'.route('procesamiento.destroy', $this->f['lote']).'"', false);
        $this->get(route('procesamiento.show', $this->f['lote']))->assertOk()->assertSee('5.123')->assertSee('kg');
    }

    public function test_operario_conserva_consulta_sin_crear_editar_o_certificar_lotes(): void
    {
        $this->actingAs($this->f['operario'])->get(route('procesamiento.index'))->assertOk()
            ->assertSee($this->f['lote']->codigo_lote)->assertDontSee('id="modalNuevoLote"', false)
            ->assertDontSee('href="'.route('procesamiento.edit', $this->f['lote']).'"', false);
        $this->get(route('procesamiento.show', $this->f['lote']))->assertOk()
            ->assertDontSee('action="'.route('procesamiento.certificar', $this->f['lote']).'"', false);
        $this->post(route('procesamiento.store'), [])->assertForbidden();
    }

    public function test_cosecha_listado_detalle_y_filtros_conservan_cantidades_y_consulta(): void
    {
        $produccion = $this->f['campoCertificable']->producciones()->first();
        $antes = $produccion->getAttributes();
        $this->actingAs($this->f['agricola'])->get(route('producciones.index', ['loteid' => $produccion->loteid]))->assertOk()
            ->assertSee('100.123456')->assertSee('kg')->assertSee('Cosechas registradas')
            ->assertDontSee('Tomate origen B');
        $this->get(route('producciones.show', $produccion))->assertOk()->assertSee('100.123456')->assertSee('kg');
        $this->assertSame($antes, $produccion->fresh()->getAttributes());
        $this->get(route('producciones.index', ['buscar' => 'Inexistente EDT45']))->assertOk()->assertDontSee('100.123456');
    }

    public function test_cantidades_sin_unidad_no_se_presentan_como_kilos_y_cero_es_valido(): void
    {
        $sinUnidad = Blade::render('<x-operacion.cantidad valor="0.000001" />');
        $this->assertStringContainsString('0.000001', $sinUnidad);
        $this->assertStringContainsString('Unidad sin registrar', $sinUnidad);
        $this->assertStringNotContainsString('kg', $sinUnidad);
        $this->assertStringContainsString('0 ', strip_tags(Blade::render('<x-operacion.cantidad :valor="0" unidad="kg" />')));
    }

    public function test_almacen_ajeno_y_ruta_anidada_con_producto_ajeno_siguen_protegidos(): void
    {
        $ajeno = CertificadosFixture::usuario('jefe_planta', 'ajeno45');
        $this->actingAs($ajeno)->get(route('almacen-planta.existencias.index', $this->f['almacen']))->assertNotFound();
        $insumo = $this->f['lote']->materiasPrimas()->first()->insumo->replicate();
        $insumo->nombre = 'Producto sin almacén';
        $insumo->almacenid = null;
        $insumo->save();
        $this->actingAs($this->f['planta'])->get(route('almacen-planta.inventario.show', [$this->f['almacen'], $insumo]))->assertNotFound();
    }
}
