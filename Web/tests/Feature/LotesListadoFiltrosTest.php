<?php

namespace Tests\Feature;

use App\Models\{Cultivo, Lote, UnidadMedida, Usuario};
use App\Support\EstadoLoteCatalogo;
use Database\Seeders\{CatalogosOperacionAgricolaSeeder, RolePermissionSeeder};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LotesListadoFiltrosTest extends TestCase
{
    use RefreshDatabase;

    private Usuario $jefe;
    private Usuario $otro;
    private Cultivo $papa;
    private Cultivo $tomate;
    private Cultivo $oculto;
    private int $planificado;
    private int $crecimiento;
    private int $certificado;
    private int $unidad;
    private Lote $norte;
    private Lote $sur;
    private Lote $mixto;
    private Lote $ajeno;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $this->jefe = $this->usuario('equipo-a');
        $this->otro = $this->usuario('equipo-b');
        $this->papa = Cultivo::create(['nombre' => 'Papa de prueba']);
        $this->tomate = Cultivo::create(['nombre' => 'Tomate de prueba']);
        $this->oculto = Cultivo::create(['nombre' => 'Cultivo privado de otro equipo']);
        $this->planificado = EstadoLoteCatalogo::idPorSlug('planificado');
        $this->crecimiento = EstadoLoteCatalogo::idPorSlug('en_crecimiento');
        $this->certificado = EstadoLoteCatalogo::idPorSlug('certificado');
        $this->unidad = UnidadMedida::firstOrCreate(['abreviatura' => 'ha'], ['nombre' => 'Hectárea', 'categoria' => 'superficie'])->unidadmedidaid;
        $this->norte = $this->lote('Parcela Norte', $this->papa, $this->planificado);
        $this->sur = $this->lote('Parcela Sur', $this->tomate, $this->crecimiento);
        $this->mixto = $this->lote('Parcela Norte auxiliar', $this->tomate, $this->planificado);
        $this->ajeno = $this->lote('Parcela Norte ajena', $this->oculto, $this->certificado, $this->otro);
        $this->actingAs($this->jefe);
    }

    private function usuario(string $nombre): Usuario
    {
        $user = Usuario::create([
            'nombre' => $nombre, 'apellido' => 'Prueba', 'email' => $nombre.'@filtros.test',
            'nombreusuario' => $nombre, 'passwordhash' => bcrypt('secret123'),
            'role' => 'jefe_agricultor', 'activo' => true, 'fecharegistro' => now(), 'fechamodificacion' => now(),
        ]);
        $user->assignRole('jefe_agricultor');

        return $user;
    }

    private function lote(string $nombre, Cultivo $cultivo, int $estado, ?Usuario $owner = null): Lote
    {
        return Lote::create([
            'usuarioid' => ($owner ?? $this->jefe)->usuarioid, 'nombre' => $nombre,
            'ubicacion' => 'ReferenciaSoloUbicacion', 'superficie' => 1, 'unidadsuperficieid' => $this->unidad,
            'codigo_trazabilidad' => 'TRAZ-'.\Illuminate\Support\Str::uuid(),
            'cultivoid' => $cultivo->cultivoid, 'estadolotetipoid' => $estado,
            'fechacreacion' => now(), 'fechamodificacion' => now(),
        ]);
    }

    private function resultados(array $params, array $expected): \Illuminate\Testing\TestResponse
    {
        $response = $this->get(route('lotes.index', $params))->assertOk();
        $this->assertSame($expected, $response->viewData('lotes')->pluck('loteid')->all());

        return $response;
    }

    public function test_listado_completo_y_catalogos_solo_del_conjunto_autorizado(): void
    {
        $response = $this->resultados([], [$this->mixto->loteid, $this->sur->loteid, $this->norte->loteid]);
        $this->assertEqualsCanonicalizing([$this->papa->cultivoid, $this->tomate->cultivoid], $response->viewData('cultivos')->modelKeys());
        $this->assertNotContains($this->certificado, $response->viewData('estados')->modelKeys());
        $this->assertNotContains($this->otro->usuarioid, $response->viewData('usuarios')->modelKeys());
    }

    public function test_nombre_completo_parcial_espacios_vacio_y_sin_buscar_ubicacion(): void
    {
        $this->resultados(['q' => 'Parcela Norte auxiliar'], [$this->mixto->loteid]);
        $this->resultados(['q' => 'Norte'], [$this->mixto->loteid, $this->norte->loteid]);
        $response = $this->resultados(['q' => '   Norte  '], [$this->mixto->loteid, $this->norte->loteid]);
        $this->assertSame('Norte', $response->viewData('filtros')['q']);
        $this->resultados(['q' => '   '], [$this->mixto->loteid, $this->sur->loteid, $this->norte->loteid]);
        $this->resultados(['q' => 'ReferenciaSoloUbicacion'], []);
        $this->resultados(['q' => $this->norte->codigo_trazabilidad], []);
    }

    public function test_comodines_comillas_y_acentos_se_tratan_como_texto(): void
    {
        foreach (['100% real' => '%', 'Sector_especial' => '_', 'Listo!Campo' => '!', "Parcela O'Hara" => "O'Hara", 'ÁREA ÑANDÚ' => 'area nandu'] as $nombre => $busqueda) {
            $lote = $this->lote($nombre, $this->papa, $this->planificado);
            $this->resultados(['q' => $busqueda], [$lote->loteid]);
        }
        $this->resultados(['q' => "' OR 1=1 --"], []);
    }

    public function test_cultivo_estado_y_combinacion_and(): void
    {
        $this->lote('Parcela Norte ajena similar', $this->papa, $this->planificado, $this->otro);
        $this->resultados(['cultivoid' => $this->papa->cultivoid], [$this->norte->loteid]);
        $this->resultados(['estadolotetipoid' => $this->planificado], [$this->mixto->loteid, $this->norte->loteid]);
        $this->resultados(['q' => 'Norte', 'cultivoid' => $this->tomate->cultivoid, 'estadolotetipoid' => $this->planificado], [$this->mixto->loteid]);
        $this->resultados(['q' => 'Norte', 'cultivoid' => $this->papa->cultivoid, 'estadolotetipoid' => $this->planificado], [$this->norte->loteid]);
        $this->resultados(['q' => 'Norte', 'cultivoid' => $this->papa->cultivoid, 'estadolotetipoid' => $this->crecimiento], [])->assertSee('No hay lotes que coincidan');
    }

    public function test_paginacion_conserva_criterios_y_el_formulario_y_limpiar_reinician_pagina(): void
    {
        $ids = [];
        for ($i = 0; $i < 17; $i++) {
            $ids[] = $this->lote('Paginación '.$i, $this->papa, $this->planificado)->loteid;
        }
        $params = ['q' => 'Paginación', 'cultivoid' => $this->papa->cultivoid, 'estadolotetipoid' => $this->planificado];
        $response = $this->get(route('lotes.index', $params))->assertOk();
        $paginator = $response->viewData('lotes');
        $this->assertSame(17, $paginator->total());
        parse_str(parse_url($paginator->nextPageUrl(), PHP_URL_QUERY), $next);
        $this->assertSame('Paginación', $next['q']);
        $this->assertSame((string) $this->papa->cultivoid, $next['cultivoid']);
        $this->assertSame((string) $this->planificado, $next['estadolotetipoid']);
        $this->resultados($params + ['page' => 2], [$ids[1], $ids[0]])->assertDontSee('name="page"', false);
        $this->assertSame($ids[16], $this->get(route('lotes.index', $params))->viewData('lotes')->first()->loteid);
        $response->assertSee(route('lotes.index', ['filtros_abiertos' => 1]));
        $this->assertSame(20, $this->get(route('lotes.index', ['filtros_abiertos' => 1]))->viewData('lotes')->total());
    }

    public function test_parametros_invalidos_y_opciones_ajenas_se_rechazan(): void
    {
        foreach ([['q' => ['x']], ['q' => str_repeat('a', 101)], ['cultivoid' => 'abc'], ['cultivoid' => -1], ['cultivoid' => 999999], ['cultivoid' => $this->oculto->cultivoid], ['estadolotetipoid' => $this->certificado], ['estadolotetipoid' => ['x']], ['usuarioid' => $this->otro->usuarioid], ['insumosemillaid' => 999999], ['page' => 0]] as $params) {
            $this->getJson(route('lotes.index', $params))->assertUnprocessable()->assertJsonValidationErrors(array_key_first($params));
        }
    }

    public function test_detalle_visible_inexistente_y_fuera_de_alcance(): void
    {
        $this->resultados(['q' => 'Norte'], [$this->mixto->loteid, $this->norte->loteid])
            ->assertSee('Ver detalle')->assertSee(route('lotes.show', $this->norte));
        $this->get(route('lotes.show', $this->norte))->assertOk()->assertSee('Parcela Norte');
        $this->getJson(route('lotes.show', $this->ajeno))->assertForbidden();
        $this->get(route('lotes.show', 999999))->assertNotFound();
    }

    public function test_listado_vacio_es_distinto_de_filtros_sin_coincidencias(): void
    {
        $this->resultados(['q' => 'inexistente'], [])->assertSee('No hay lotes que coincidan');
        $sinLotes = $this->usuario('equipo-vacio');
        $this->actingAs($sinLotes);
        $this->resultados([], [])->assertSee('No hay lotes disponibles');
    }
}
