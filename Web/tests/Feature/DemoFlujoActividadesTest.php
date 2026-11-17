<?php

namespace Tests\Feature;

use App\Models\{Actividad, AlmacenMovimiento, Insumo, Lote, LoteInsumo, Usuario};
use App\Support\InventarioDecimal;
use Database\Seeders\{CatalogosOperacionAgricolaSeeder, DemoFlujoActividadesSeeder, RolePermissionSeeder};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class DemoFlujoActividadesTest extends TestCase
{
    use RefreshDatabase;

    public function test_demo_completa_flujo_real_y_repetir_no_duplica_ni_reinicia_stock(): void
    {
        Storage::fake('local');
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class, DemoFlujoActividadesSeeder::class]);
        $this->assertSame(4, Lote::where('nombre', 'like', 'DEMO EDT - %')->count());
        $this->assertSame(12, Actividad::where('descripcion', 'like', 'DEMO EDT %')->count());
        $this->assertSame(5, Actividad::whereNotNull('fechafin')->count());
        $this->assertSame(2, LoteInsumo::count());
        $this->assertSame(2, AlmacenMovimiento::count());
        $this->assertCount(4, Storage::disk('local')->allFiles('actividades_privadas'));
        Storage::disk('local')->assertExists('demo-flujo/foto-prueba-cierre.png');
        $fertilizante = Insumo::where('nombre', 'DEMO EDT - Fertilizante')->firstOrFail();
        $this->assertSame('97.500000', InventarioDecimal::texto(InventarioDecimal::unidades($fertilizante->getRawOriginal('stock'))));
        $antes = [Usuario::count(), Actividad::count(), LoteInsumo::count(), AlmacenMovimiento::count(), Storage::disk('local')->allFiles()];
        $this->seed(DemoFlujoActividadesSeeder::class);
        $this->assertSame($antes, [Usuario::count(), Actividad::count(), LoteInsumo::count(), AlmacenMovimiento::count(), Storage::disk('local')->allFiles()]);
        $this->assertSame('97.500000', InventarioDecimal::texto(InventarioDecimal::unidades($fertilizante->fresh()->getRawOriginal('stock'))));
        $jefe = Usuario::where('email', 'jefe.agricultor@agrofusion.local')->firstOrFail();
        $this->actingAs($jefe, 'web')->get(route('actividades.calendario', [
            'start' => now()->subDays(7)->toDateString(), 'end' => now()->addDays(7)->toDateString(),
        ]), ['Accept' => 'application/json'])->assertOk()->assertJsonCount(11, 'eventos');
    }
}
