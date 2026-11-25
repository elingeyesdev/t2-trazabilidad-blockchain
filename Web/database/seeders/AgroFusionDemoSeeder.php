<?php

namespace Database\Seeders;

use App\Models\Actividad;
use App\Models\Almacen;
use App\Models\AlmacenajeLoteProduccion;
use App\Models\AlmacenMovimiento;
use App\Models\CatalogoTamanoConteo;
use App\Models\CertificacionLote;
use App\Models\ChecklistCondicionLogistica;
use App\Models\Cultivo;
use App\Models\DestinoProduccion;
use App\Models\DetallePedido;
use App\Models\DetallePedidoDistribucion;
use App\Models\DetalleTrasladoPlantaMayorista;
use App\Models\EnvioAsignacionMultiple;
use App\Models\EstadoLoteInsumo;
use App\Models\EstadoTransportista;
use App\Models\EstadoVehiculo;
use App\Models\EvaluacionFinalLoteProduccion;
use App\Models\FirmaRecepcionEnvio;
use App\Models\FirmaTransportistaEnvio;
use App\Models\HistorialEstadoLote;
use App\Models\Insumo;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\Lote;
use App\Models\LoteInsumo;
use App\Models\LoteProduccionMateriaPrima;
use App\Models\LoteProduccionPedido;
use App\Models\MaquinaPlanta;
use App\Models\MateriaPrimaLote;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\PerfilTransportista;
use App\Models\PlantillaTransformacion;
use App\Models\Prioridad;
use App\Models\ProcesoMaquinaPlanta;
use App\Models\ProcesoPlanta;
use App\Models\Produccion;
use App\Models\ProduccionAlmacenamiento;
use App\Models\PuntoVenta;
use App\Models\RegistroProcesoMaquinaPlanta;
use App\Models\RutaDistribucion;
use App\Models\RutaDistribucionParada;
use App\Models\TipoActividad;
use App\Models\TipoAlmacen;
use App\Models\TipoEmpaque;
use App\Models\TipoInsumo;
use App\Models\TipoMovimientoAlmacen;
use App\Models\TipoTransporte;
use App\Models\TipoVehiculo;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Models\Vehiculo;
use App\Support\AlmacenAmbito;
use App\Support\CuentaEstado;
use App\Support\EmpaquePlantaCatalogo;
use App\Support\EstadoLoteCatalogo;
use App\Support\InsumoCatalogo;
use App\Support\LoteDefaults;
use App\Support\PedidoCatalogo;
use App\Support\PedidoDistribucionCatalogo;
use App\Support\RutaDistribucionCatalogo;
use App\Support\TransportistaFlotaCatalogo;
use App\Support\TrazabilidadProductoPdvService;
use Carbon\Carbon;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Spatie\Permission\Models\Role;

/**
 * Seeder maestro de demostración de AgroFusion.
 *
 * - Contraseña única para todas las cuentas: 12345
 * - Catálogos limpios sin duplicados ni roles legacy
 * - 2 recorridos completos de trazabilidad 5 etapas (Campo → Planta → Mayorista → Distribución → PDV + QR)
 * - Escenarios activos en cada módulo listos para demostración en vivo (Web y Mobile)
 *
 * Ejecutar limpio: php artisan migrate:fresh --seed
 */
class AgroFusionDemoSeeder extends Seeder
{
    public const DEMO_PASSWORD = '12345';

    /** @var array<string, UnidadMedida> */
    private array $unidades = [];

    /** @var array<string, TipoInsumo> */
    private array $tiposInsumo = [];

    /** @var array<string, TipoAlmacen> */
    private array $tiposAlmacen = [];

    /** @var array<string, TipoMovimientoAlmacen> */
    private array $tiposMovimiento = [];

    /** @var array<string, TipoEmpaque> */
    private array $tiposEmpaque = [];

    /** @var array<string, Cultivo> */
    private array $cultivos = [];

    /** @var array<string, TipoTransporte> */
    private array $tiposTransporte = [];

    /** @var array<string, TipoVehiculo> */
    private array $tiposVehiculo = [];

    /** @var array<string, Vehiculo> */
    private array $vehiculos = [];

    /** @var array<string, Usuario> */
    private array $usuarios = [];

    /** @var array<string, Almacen> */
    private array $almacenes = [];

    /** @var array<string, PuntoVenta> */
    private array $puntosVenta = [];

    /** @var array<string, Insumo> */
    private array $insumosCampo = [];

    public function run(): void
    {
        // Eliminar cualquier insumo huérfano (almacenid IS NULL) insertado por migraciones históricas
        if (Schema::hasTable('insumo')) {
            Insumo::query()->whereNull('almacenid')->delete();
        }

        $this->seedCatalogosBase();
        $this->seedCatalogosPlanta();
        $this->seedCatalogosLogisticaYFlota();

        DB::transaction(function () {
            $this->seedUsuarios();
            $this->seedAlmacenesYPuntosVenta();
            $this->seedInventarioInicialCampoYPlanta();

            // Cadena 1: Tomate → Salsa de Tomate Artesanal → Mayorista → Mercado Alvaro (QR)
            $cadenaTomate = $this->seedCadenaTrazabilidadCompleta([
                'cultivo' => 'Tomate',
                'lote_nombre' => 'Tomate - Lote 001',
                'lote_codigo' => 'TRAZ-TOM-2026-001',
                'semilla_key' => 'semilla_tomate',
                'semilla_kg' => 50.0,
                'fert_kg' => 120.0,
                'plaga_cant' => 15.0,
                'superficie_ha' => 3.5,
                'lat' => -17.7165,
                'lng' => -63.1662,
                'ubicacion' => 'Finca Norte, Km 9 Av. Banzer, Santa Cruz',
                'cosecha_kg' => 2500.0,
                'envio_kg' => 1500.0,
                'cert_codigo' => 'CERT-TOM-2026-001',
                'pedido_num' => 'PED-20261105-0001',
                'envio_ext' => 'ENV-TOM-2026-001',
                'vehiculo_agr' => 'SCZ-AGR-01',
                'chofer_agr' => 'chofer_agr1',
                'mp_nombre' => 'Tomate fresco de campo',
                'mp_lote_codigo' => 'MPL-TOM-2026-001',
                'mp_usada_kg' => 1200.0,
                'plantilla_nombre' => 'Salsa de tomate',
                'lote_planta_codigo' => 'LPP-20261108-001',
                'producto_nombre' => 'Salsa de Tomate Artesanal',
                'presentacion_nombre' => 'Frasco 340 g',
                'tipo_envase' => 'frasco',
                'empaque_slug' => 'frasco',
                'peso_neto_kg' => 0.34,
                'sku' => 'SKU-SALSA-340G',
                'unidades_producidas' => 3000,
                'unidades_mayorista' => 2000,
                'unidades_pdv' => 400,
                'cert_planta_codigo' => 'CERT-PLT-TOM-2026-001',
                'ruta_pm_codigo' => 'TPM-20261112-0001',
                'pedido_pdv_num' => 'PDV-20261116-0001',
                'ruta_pdv_codigo' => 'RUT-PDV-20261116-001',
                'qr_codigo' => 'TRZ-PDV-TOMATE-202601',
                'dias_inicio' => 75,
            ]);

            // Cadena 2: Papa → Papas Fritas Artesanales → Mayorista → Mercado Alvaro (QR)
            $this->seedCadenaTrazabilidadCompleta([
                'cultivo' => 'Papa',
                'lote_nombre' => 'Papa - Lote 001',
                'lote_codigo' => 'TRAZ-PAP-2026-001',
                'semilla_key' => 'semilla_papa',
                'semilla_kg' => 180.0,
                'fert_kg' => 150.0,
                'plaga_cant' => 12.0,
                'superficie_ha' => 4.0,
                'lat' => -17.8540,
                'lng' => -63.2680,
                'ubicacion' => 'Parcela Valles, Km 14 Carretera a Samaipata, Santa Cruz',
                'cosecha_kg' => 3000.0,
                'envio_kg' => 1800.0,
                'cert_codigo' => 'CERT-PAP-2026-001',
                'pedido_num' => 'PED-20261107-0001',
                'envio_ext' => 'ENV-PAP-2026-001',
                'vehiculo_agr' => 'SCZ-AGR-02',
                'chofer_agr' => 'chofer_agr2',
                'mp_nombre' => 'Papa fresca de campo',
                'mp_lote_codigo' => 'MPL-PAP-2026-001',
                'mp_usada_kg' => 1765.0,
                'plantilla_nombre' => 'Papa frita congelada',
                'lote_planta_codigo' => 'LPP-20261110-001',
                'producto_nombre' => 'Papas Fritas Artesanales',
                'presentacion_nombre' => 'Bolsa 500 g',
                'tipo_envase' => 'bolsa',
                'empaque_slug' => 'bolsa',
                'peso_neto_kg' => 0.50,
                'sku' => 'SKU-PAPAS-500G',
                'unidades_producidas' => 3000,
                'unidades_mayorista' => 2000,
                'unidades_pdv' => 400,
                'cert_planta_codigo' => 'CERT-PLT-PAP-2026-001',
                'ruta_pm_codigo' => 'TPM-20261114-0001',
                'pedido_pdv_num' => 'PDV-20261118-0001',
                'ruta_pdv_codigo' => 'RUT-PDV-20261118-001',
                'qr_codigo' => 'TRZ-PDV-PAPA-202601',
                'dias_inicio' => 82,
            ]);

            // Escenarios activos en curso para demostración en vivo (Web + Mobile)
            $this->seedEscenariosActivosDemo($cadenaTomate);
        });

        $this->imprimirResumen();
    }

    private function seedCatalogosBase(): void
    {
        $this->call(RolePermissionSeeder::class);
        $this->call(CatalogosOperacionAgricolaSeeder::class);
        InsumoCatalogo::asegurarCatalogosBase();

        // Unidades adicionales limpias
        $unidadesExtra = [
            ['nombre' => 'Hectárea', 'abreviatura' => 'ha', 'categoria' => 'area'],
            ['nombre' => 'Tonelada', 'abreviatura' => 't', 'categoria' => 'peso'],
            ['nombre' => 'Caja', 'abreviatura' => 'cj', 'categoria' => 'cantidad'],
        ];
        foreach ($unidadesExtra as $u) {
            UnidadMedida::updateOrCreate(['nombre' => $u['nombre']], $u);
        }

        foreach (UnidadMedida::all() as $u) {
            $key = mb_strtolower(trim((string) ($u->abreviatura ?: $u->nombre)));
            $this->unidades[$key] = $u;
        }

        // Tipos de insumo complementarios (sin duplicar los 3 canónicos de InsumoCatalogo)
        foreach (['Materia prima', 'Producto terminado', 'Insumo de procesamiento'] as $nombre) {
            TipoInsumo::firstOrCreate(['nombre' => $nombre]);
        }
        foreach (TipoInsumo::all() as $t) {
            $this->tiposInsumo[mb_strtolower(trim($t->nombre))] = $t;
        }

        // Tipos de almacén
        $tiposAlm = [
            'agricola' => ['nombre' => 'Almacén Agrícola', 'descripcion' => 'Insumos y cosechas de campo'],
            'planta' => ['nombre' => 'Almacén de Planta', 'descripcion' => 'Materias primas y productos terminados de planta'],
            'mayorista' => ['nombre' => 'Centro Mayorista', 'descripcion' => 'Distribución mayorista hacia puntos de venta'],
            'pdv' => ['nombre' => 'Punto de Venta', 'descripcion' => 'Inventario minorista para consumidor final'],
        ];
        foreach ($tiposAlm as $key => $def) {
            $this->tiposAlmacen[$key] = TipoAlmacen::updateOrCreate(['nombre' => $def['nombre']], $def);
        }

        // Tipos de movimiento de almacén
        $movimientos = [
            'compra' => ['nombre' => 'Compra', 'naturaleza' => 'ingreso'],
            'ingreso_inicial' => ['nombre' => 'Ingreso inicial', 'naturaleza' => 'ingreso'],
            'produccion_recibida' => ['nombre' => 'Producción recibida', 'naturaleza' => 'ingreso'],
            'ajuste_positivo' => ['nombre' => 'Ajuste positivo', 'naturaleza' => 'ingreso'],
            'devolucion' => ['nombre' => 'Devolución', 'naturaleza' => 'ingreso'],
            'consumo_interno' => ['nombre' => 'Consumo interno', 'naturaleza' => 'egreso'],
            'despacho' => ['nombre' => 'Despacho', 'naturaleza' => 'egreso'],
            'envio' => ['nombre' => 'Envío', 'naturaleza' => 'egreso'],
            'ajuste_negativo' => ['nombre' => 'Ajuste negativo', 'naturaleza' => 'egreso'],
            'merma' => ['nombre' => 'Merma', 'naturaleza' => 'egreso'],
        ];
        foreach ($movimientos as $key => $def) {
            $this->tiposMovimiento[$key] = TipoMovimientoAlmacen::updateOrCreate(
                ['nombre' => $def['nombre']],
                ['naturaleza' => $def['naturaleza'], 'activo' => true]
            );
        }

        // Cultivos
        $cultivos = [
            ['nombre' => 'Tomate', 'detalle' => 'Tomate perita de alta productividad para industria y mesa', 'dosis_siembra_por_ha' => 15, 'dosis_siembra_unidad' => 'kg'],
            ['nombre' => 'Papa', 'detalle' => 'Papa Huaycha seleccionada para procesamiento y consumo', 'dosis_siembra_por_ha' => 45, 'dosis_siembra_unidad' => 'kg'],
            ['nombre' => 'Zanahoria', 'detalle' => 'Zanahoria Imperator de raíz uniforme', 'dosis_siembra_por_ha' => 12, 'dosis_siembra_unidad' => 'kg'],
            ['nombre' => 'Cebolla', 'detalle' => 'Cebolla roja de bulbo firme', 'dosis_siembra_por_ha' => 10, 'dosis_siembra_unidad' => 'kg'],
            ['nombre' => 'Lechuga', 'detalle' => 'Lechuga crespa fresca de ciclo corto', 'dosis_siembra_por_ha' => 6, 'dosis_siembra_unidad' => 'kg'],
        ];
        foreach ($cultivos as $c) {
            $this->cultivos[$c['nombre']] = Cultivo::updateOrCreate(['nombre' => $c['nombre']], $c);
        }

        // Estados de lote (canónicos)
        foreach (['planificado', 'sembrado', 'en_crecimiento', 'listo_para_cosecha', 'cosechado', 'certificado', 'finalizado'] as $slug) {
            EstadoLoteCatalogo::idPorSlug($slug);
        }

        // Estados de insumo en lote y destinos de producción
        foreach (['Planificado', 'Aplicado', 'Cancelado'] as $nombre) {
            EstadoLoteInsumo::firstOrCreate(['nombre' => $nombre]);
        }
        foreach (['Almacén agrícola', 'Planta procesadora', 'Venta directa'] as $nombre) {
            DestinoProduccion::firstOrCreate(['nombre' => $nombre]);
        }

        // Empaques industriales + agrícolas
        EmpaquePlantaCatalogo::asegurarTiposEmpaqueEnBd();
        $empaquesAgr = [
            ['nombre' => 'Caja plástica cosechera', 'descripcion' => 'Caja ventilada de 20 kg para hortalizas frescas', 'largo_cm' => 50, 'ancho_cm' => 35, 'alto_cm' => 30, 'tara_kg' => 1.5, 'capacidad_unidades' => 20, 'unidades_por_pallet' => 40, 'ambito' => 'agricola', 'activo' => true],
            ['nombre' => 'Saco agrícola', 'descripcion' => 'Saco tejido de polipropileno para tubérculos (50 kg)', 'largo_cm' => 75, 'ancho_cm' => 50, 'alto_cm' => 22, 'tara_kg' => 0.25, 'capacidad_unidades' => 50, 'unidades_por_pallet' => 24, 'ambito' => 'agricola', 'activo' => true],
            ['nombre' => 'Caja de cartón', 'descripcion' => 'Caja corrugada reforzada para despacho (15 kg)', 'largo_cm' => 45, 'ancho_cm' => 32, 'alto_cm' => 25, 'tara_kg' => 0.8, 'capacidad_unidades' => 15, 'unidades_por_pallet' => 48, 'ambito' => 'agricola', 'activo' => true],
        ];
        foreach ($empaquesAgr as $e) {
            TipoEmpaque::updateOrCreate(['nombre' => $e['nombre']], $e);
        }
        foreach (TipoEmpaque::all() as $te) {
            $this->tiposEmpaque[mb_strtolower(trim($te->nombre))] = $te;
        }
    }

    private function seedCatalogosPlanta(): void
    {
        $this->call([
            ProcesosPlantaOperativosSeeder::class,
            MaquinasProcesoPlantaSeeder::class,
            PlantillasTransformacionSeeder::class,
        ]);
    }

    private function seedCatalogosLogisticaYFlota(): void
    {
        // Tipos de transporte
        $transportes = [
            ['codigo' => 'CARGA_GENERAL', 'nombre' => 'Carga general', 'descripcion' => 'Transporte seco o a temperatura ambiente'],
            ['codigo' => 'REFRIGERADO', 'nombre' => 'Refrigerado', 'descripcion' => 'Cadena de frío controlada (2 °C a 8 °C)'],
            ['codigo' => 'ISOTERMICO', 'nombre' => 'Isotérmico', 'descripcion' => 'Caja aislada térmicamente para traslados medianos'],
            ['codigo' => 'MULTITEMPERATURA', 'nombre' => 'Multitemperatura', 'descripcion' => 'Compartimientos separados para carga seca y fría'],
        ];
        foreach ($transportes as $t) {
            $this->tiposTransporte[$t['codigo']] = TipoTransporte::updateOrCreate(['codigo' => $t['codigo']], $t);
        }

        // Tipos de vehículo
        $tiposVeh = [
            [
                'codigo' => 'CAMIONETA', 'nombre' => 'Camioneta', 'tamano' => 'pequeno',
                'descripcion' => 'Vehículo liviano para entregas rápidas urbanas y de finca',
                'capacidad_kg' => 1500, 'capacidad_m3' => 8, 'licencia_requerida' => 'A',
                'largo_m' => 2.4, 'ancho_m' => 1.6, 'alto_m' => 1.5, 'factor_volumen_util' => 0.85,
                'transportes' => ['CARGA_GENERAL'],
            ],
            [
                'codigo' => 'CAMION_PQ', 'nombre' => 'Camión pequeño', 'tamano' => 'mediano',
                'descripcion' => 'Camión mediano de reparto y acopio agrícola',
                'capacidad_kg' => 3500, 'capacidad_m3' => 15, 'licencia_requerida' => 'B',
                'largo_m' => 4.2, 'ancho_m' => 2.0, 'alto_m' => 1.9, 'factor_volumen_util' => 0.85,
                'transportes' => ['CARGA_GENERAL', 'REFRIGERADO', 'ISOTERMICO'],
            ],
            [
                'codigo' => 'CAMION_GR', 'nombre' => 'Camión grande', 'tamano' => 'grande',
                'descripcion' => 'Camión pesado de alto tonelaje para planta y mayorista',
                'capacidad_kg' => 10000, 'capacidad_m3' => 40, 'licencia_requerida' => 'C',
                'largo_m' => 7.2, 'ancho_m' => 2.4, 'alto_m' => 2.4, 'factor_volumen_util' => 0.88,
                'transportes' => ['CARGA_GENERAL', 'REFRIGERADO', 'ISOTERMICO', 'MULTITEMPERATURA'],
            ],
        ];
        foreach ($tiposVeh as $def) {
            $codigosTransp = $def['transportes'];
            unset($def['transportes']);
            $def['activo'] = true;
            $tv = TipoVehiculo::updateOrCreate(['codigo' => $def['codigo']], $def);
            $this->tiposVehiculo[$def['codigo']] = $tv;

            if (Schema::hasTable('tipo_vehiculo_tipo_transporte')) {
                $ids = collect($codigosTransp)->map(fn (string $c) => $this->tiposTransporte[$c]->tipotransporteid)->all();
                $tv->tiposTransporte()->sync($ids);
            }
        }

        // Estados de vehículo, transportista y asignación
        foreach (['operativo', 'mantenimiento', 'baja'] as $nombre) {
            EstadoVehiculo::firstOrCreate(['nombre' => $nombre]);
        }
        foreach (['Disponible', 'En ruta', 'Inactivo'] as $nombre) {
            EstadoTransportista::firstOrCreate(['nombre' => $nombre]);
        }
        if (Schema::hasTable('estado_asignacion_multiple_catalogo')) {
            foreach (['pendiente', 'asignado', 'en_transporte_planta', 'recibido_planta', 'cancelado'] as $nombre) {
                DB::table('estado_asignacion_multiple_catalogo')->updateOrInsert(['nombre' => $nombre], ['nombre' => $nombre]);
            }
        }
        if (Schema::hasTable('condicion_transporte')) {
            $condiciones = [
                ['codigo' => 'TEMP_OK', 'titulo' => 'Temperatura controlada dentro de rango', 'descripcion' => 'La carga llegó con temperatura adecuada.'],
                ['codigo' => 'EMPAQUE_OK', 'titulo' => 'Empaques íntegros y sellados', 'descripcion' => 'Sin cajas aplastadas ni envases rotos.'],
                ['codigo' => 'CANTIDAD_OK', 'titulo' => 'Cantidad completa conforme a guía', 'descripcion' => 'Peso y bultos coinciden con el despacho.'],
                ['codigo' => 'LIMPIEZA_OK', 'titulo' => 'Higiene y limpieza del vehículo', 'descripcion' => 'Caja de carga limpia y libre de contaminantes.'],
                ['codigo' => 'DOC_OK', 'titulo' => 'Documentación completa', 'descripcion' => 'Guía de remisión y certificado disponibles.'],
            ];
            foreach ($condiciones as $c) {
                DB::table('condicion_transporte')->updateOrInsert(['codigo' => $c['codigo']], array_merge($c, ['created_at' => now(), 'updated_at' => now()]));
            }
        }
        if (Schema::hasTable('tipo_incidente_transporte')) {
            $incidentes = [
                ['codigo' => 'RETRASO', 'titulo' => 'Retraso en ruta', 'descripcion' => 'Demora por tráfico, clima o bloqueos.'],
                ['codigo' => 'FALLA_FRIO', 'titulo' => 'Variación de temperatura', 'descripcion' => 'Desviación en el equipo de refrigeración.'],
                ['codigo' => 'DANO_EMPAQUE', 'titulo' => 'Daño parcial de empaque', 'descripcion' => 'Envases o cajas dañadas durante el trayecto.'],
                ['codigo' => 'FALLA_MEC', 'titulo' => 'Falla mecánica', 'descripcion' => 'Avería del vehículo en ruta.'],
                ['codigo' => 'FALTANTE', 'titulo' => 'Diferencia de cantidad', 'descripcion' => 'Faltante detectado en la recepción.'],
            ];
            foreach ($incidentes as $i) {
                DB::table('tipo_incidente_transporte')->updateOrInsert(['codigo' => $i['codigo']], array_merge($i, ['created_at' => now(), 'updated_at' => now()]));
            }
        }

        // Flota de 7 vehículos (3 agrícolas, 2 planta, 2 mayorista)
        $estadoOperativoId = EstadoVehiculo::where('nombre', 'operativo')->value('estadovehiculoid');
        $flota = [
            ['placa' => 'SCZ-AGR-01', 'marca' => 'Volvo', 'modelo' => 'FH 460', 'anio' => 2023, 'color' => 'Blanco', 'tipo' => 'CAMION_GR', 'ambito' => TransportistaFlotaCatalogo::AGRICOLA, 'transp' => ['CARGA_GENERAL', 'REFRIGERADO', 'MULTITEMPERATURA']],
            ['placa' => 'SCZ-AGR-02', 'marca' => 'Hino', 'modelo' => 'Serie 300', 'anio' => 2024, 'color' => 'Blanco', 'tipo' => 'CAMION_PQ', 'ambito' => TransportistaFlotaCatalogo::AGRICOLA, 'transp' => ['CARGA_GENERAL', 'REFRIGERADO', 'ISOTERMICO']],
            ['placa' => 'SCZ-AGR-03', 'marca' => 'Toyota', 'modelo' => 'Hilux 4x4', 'anio' => 2025, 'color' => 'Plata', 'tipo' => 'CAMIONETA', 'ambito' => TransportistaFlotaCatalogo::AGRICOLA, 'transp' => ['CARGA_GENERAL']],
            ['placa' => 'SCZ-PLT-01', 'marca' => 'Mercedes-Benz', 'modelo' => 'Atego 1726', 'anio' => 2024, 'color' => 'Blanco', 'tipo' => 'CAMION_GR', 'ambito' => TransportistaFlotaCatalogo::PLANTA, 'transp' => ['CARGA_GENERAL', 'REFRIGERADO', 'MULTITEMPERATURA']],
            ['placa' => 'SCZ-PLT-02', 'marca' => 'Isuzu', 'modelo' => 'NPR 75', 'anio' => 2023, 'color' => 'Azul', 'tipo' => 'CAMION_PQ', 'ambito' => TransportistaFlotaCatalogo::PLANTA, 'transp' => ['CARGA_GENERAL', 'REFRIGERADO']],
            ['placa' => 'SCZ-MAY-01', 'marca' => 'Hyundai', 'modelo' => 'HD78 Furgón', 'anio' => 2024, 'color' => 'Blanco', 'tipo' => 'CAMION_PQ', 'ambito' => TransportistaFlotaCatalogo::MAYORISTA, 'transp' => ['CARGA_GENERAL', 'REFRIGERADO', 'ISOTERMICO']],
            ['placa' => 'SCZ-MAY-02', 'marca' => 'Nissan', 'modelo' => 'Frontier NP300', 'anio' => 2025, 'color' => 'Gris', 'tipo' => 'CAMIONETA', 'ambito' => TransportistaFlotaCatalogo::MAYORISTA, 'transp' => ['CARGA_GENERAL']],
        ];
        foreach ($flota as $f) {
            $v = Vehiculo::updateOrCreate(
                ['placa' => $f['placa']],
                [
                    'marca' => $f['marca'],
                    'modelo' => $f['modelo'],
                    'anio' => $f['anio'],
                    'color' => $f['color'],
                    'tipovehiculoid' => $this->tiposVehiculo[$f['tipo']]->tipovehiculoid,
                    'estadovehiculoid' => $estadoOperativoId,
                    'ambito_flota' => $f['ambito'],
                    'activo' => true,
                ]
            );
            $this->vehiculos[$f['placa']] = $v;

            if (Schema::hasTable('vehiculo_tipo_transporte')) {
                $ids = collect($f['transp'])->map(fn (string $c) => $this->tiposTransporte[$c]->tipotransporteid)->all();
                $v->tiposTransporte()->sync($ids);
            }
        }
    }

    private function seedUsuarios(): void
    {
        $passwordHash = Hash::make(self::DEMO_PASSWORD);
        $estadoDispId = EstadoTransportista::where('nombre', 'Disponible')->value('estadotransportistaid');

        $definiciones = [
            'admin' => [
                'email' => 'admin@agrofusion.com', 'nombre' => 'Administrador', 'apellido' => 'AgroFusion',
                'nombreusuario' => 'admin', 'telefono' => '70000001', 'role' => 'admin',
            ],
            'jefe_agricola' => [
                'email' => 'jefe.agricola@agrofusion.com', 'nombre' => 'Andre', 'apellido' => 'Romero',
                'nombreusuario' => 'jefe.agricola', 'telefono' => '70000002', 'role' => 'jefe_agricultor',
            ],
            'agricultor' => [
                'email' => 'agricultor@agrofusion.com', 'nombre' => 'Roberto', 'apellido' => 'Mar',
                'nombreusuario' => 'agricultor', 'telefono' => '70000003', 'role' => 'agricultor',
                'supervisor' => 'jefe_agricola',
            ],
            'agricultor2' => [
                'email' => 'agricultor2@agrofusion.com', 'nombre' => 'Luis', 'apellido' => 'Guerrero',
                'nombreusuario' => 'agricultor2', 'telefono' => '70000004', 'role' => 'agricultor',
                'supervisor' => 'jefe_agricola',
            ],
            'jefe_planta' => [
                'email' => 'jefe.planta@agrofusion.com', 'nombre' => 'Jhon', 'apellido' => 'Rojas',
                'nombreusuario' => 'jefe.planta', 'telefono' => '70000005', 'role' => 'jefe_planta',
            ],
            'planta' => [
                'email' => 'planta@agrofusion.com', 'nombre' => 'Carlos', 'apellido' => 'Rueda',
                'nombreusuario' => 'planta', 'telefono' => '70000006', 'role' => 'planta',
                'supervisor' => 'jefe_planta',
            ],
            'jefe_mayorista' => [
                'email' => 'jefe.mayorista@agrofusion.com', 'nombre' => 'Valeria', 'apellido' => 'Mendoza',
                'nombreusuario' => 'jefe.mayorista', 'telefono' => '70000007', 'role' => 'jefe_mayorista',
            ],
            'mayorista' => [
                'email' => 'mayorista@agrofusion.com', 'nombre' => 'Diego', 'apellido' => 'Roca',
                'nombreusuario' => 'mayorista', 'telefono' => '70000008', 'role' => 'mayorista',
                'supervisor' => 'jefe_mayorista',
            ],
            'minorista' => [
                'email' => 'minorista@agrofusion.com', 'nombre' => 'Alvaro', 'apellido' => 'Gutierrez',
                'nombreusuario' => 'minorista', 'telefono' => '70000009', 'role' => 'minorista',
            ],
            'chofer_agr1' => [
                'email' => 'chofer.agricola@agrofusion.com', 'nombre' => 'Carlos', 'apellido' => 'Mamani',
                'nombreusuario' => 'chofer.agricola', 'telefono' => '70000010', 'role' => 'transportista',
                'supervisor' => 'jefe_agricola',
                'tipo_licencia' => 'C', 'licencias' => ['A', 'B', 'C'],
                'flota' => TransportistaFlotaCatalogo::AGRICOLA, 'placa' => 'SCZ-AGR-01', 'lic_num' => 'LIC-SCZ-8801',
            ],
            'chofer_agr2' => [
                'email' => 'chofer.agricola2@agrofusion.com', 'nombre' => 'Marco', 'apellido' => 'Polo',
                'nombreusuario' => 'chofer.agricola2', 'telefono' => '70000011', 'role' => 'transportista',
                'supervisor' => 'jefe_agricola',
                'tipo_licencia' => 'B', 'licencias' => ['A', 'B'],
                'flota' => TransportistaFlotaCatalogo::AGRICOLA, 'placa' => 'SCZ-AGR-02', 'lic_num' => 'LIC-SCZ-8802',
            ],
            'chofer_planta' => [
                'email' => 'chofer.planta@agrofusion.com', 'nombre' => 'Mario', 'apellido' => 'Vargas',
                'nombreusuario' => 'chofer.planta', 'telefono' => '70000012', 'role' => 'transportista',
                'supervisor' => 'jefe_planta',
                'tipo_licencia' => 'C', 'licencias' => ['A', 'B', 'C'],
                'flota' => TransportistaFlotaCatalogo::PLANTA, 'placa' => 'SCZ-PLT-01', 'lic_num' => 'LIC-SCZ-8803',
            ],
            'chofer_mayorista' => [
                'email' => 'chofer.mayorista@agrofusion.com', 'nombre' => 'Pedro', 'apellido' => 'Morales',
                'nombreusuario' => 'chofer.mayorista', 'telefono' => '70000013', 'role' => 'transportista',
                'supervisor' => 'jefe_mayorista',
                'tipo_licencia' => 'B', 'licencias' => ['A', 'B'],
                'flota' => TransportistaFlotaCatalogo::MAYORISTA, 'placa' => 'SCZ-MAY-01', 'lic_num' => 'LIC-SCZ-8804',
            ],
        ];

        foreach ($definiciones as $key => $def) {
            $supervisorId = isset($def['supervisor']) ? $this->usuarios[$def['supervisor']]->usuarioid : null;
            $u = Usuario::updateOrCreate(
                ['email' => $def['email']],
                [
                    'nombre' => $def['nombre'],
                    'apellido' => $def['apellido'],
                    'nombreusuario' => $def['nombreusuario'],
                    'telefono' => $def['telefono'],
                    'passwordhash' => $passwordHash,
                    'role' => $def['role'],
                    'activo' => true,
                    'estado_cuenta' => CuentaEstado::APROBADO,
                    'supervisor_usuarioid' => $supervisorId,
                    'tipo_licencia' => $def['tipo_licencia'] ?? null,
                    'licencias_json' => $def['licencias'] ?? null,
                    'bienvenida_vista' => true,
                    'fecharegistro' => now()->subDays(90),
                    'fechamodificacion' => now(),
                ]
            );
            Role::firstOrCreate(['name' => $def['role'], 'guard_name' => 'web']);
            $u->syncRoles([$def['role']]);
            $this->usuarios[$key] = $u;

            if (isset($def['flota'])) {
                PerfilTransportista::updateOrCreate(
                    ['usuarioid' => $u->usuarioid],
                    [
                        'estadotransportistaid' => $estadoDispId,
                        'vehiculoid' => $this->vehiculos[$def['placa']]->vehiculoid,
                        'licencia' => $def['lic_num'],
                        'tipo_licencia' => $def['tipo_licencia'],
                        'licencias_json' => $def['licencias'],
                        'fecha_vencimiento_licencia' => now()->addYears(3)->toDateString(),
                        'disponible' => true,
                        'ambito_flota' => $def['flota'],
                    ]
                );
            }
        }

        // 1 solicitud de cuenta pendiente para demostrar flujo de aprobación
        Usuario::updateOrCreate(
            ['email' => 'nuevo.agricultor@agrofusion.com'],
            [
                'nombre' => 'Sofía',
                'apellido' => 'Flores',
                'nombreusuario' => 'sofia.flores',
                'telefono' => '70000099',
                'passwordhash' => $passwordHash,
                'role' => 'agricultor',
                'rol_solicitado' => 'agricultor',
                'ci_nit' => '7845120 SC',
                'carta_motivacion' => 'Productora agrícola en la zona norte de Santa Cruz interesada en registrar lotes y cosechas con trazabilidad.',
                'activo' => false,
                'estado_cuenta' => CuentaEstado::PENDIENTE,
                'fecharegistro' => now()->subDay(),
                'fechamodificacion' => now(),
            ]
        );
    }

    private function seedAlmacenesYPuntosVenta(): void
    {
        $kgId = $this->unidades['kg']->unidadmedidaid;

        $this->almacenes['agr_norte'] = Almacen::updateOrCreate(
            ['codigo' => 'ALM-AGR-01'],
            [
                'nombre' => 'Almacén Agrícola Norte',
                'descripcion' => 'Almacén principal de insumos agrícolas y cosecha fresca — Zona Norte.',
                'ubicacion' => 'Av. Banzer Km 9, Zona Norte, Santa Cruz (-17.7165, -63.1662)',
                'capacidad' => 15000,
                'unidadmedidaid' => $kgId,
                'tipoalmacenid' => $this->tiposAlmacen['agricola']->tipoalmacenid,
                'ambito' => AlmacenAmbito::AGRICOLA,
                'responsable_usuarioid' => $this->usuarios['jefe_agricola']->usuarioid,
                'activo' => true,
            ]
        );

        $this->almacenes['agr_valles'] = Almacen::updateOrCreate(
            ['codigo' => 'ALM-AGR-02'],
            [
                'nombre' => 'Almacén Agrícola Valles',
                'descripcion' => 'Almacén secundario para cultivos de valles cruceños.',
                'ubicacion' => 'Carretera a Samaipata Km 14, Santa Cruz (-17.8540, -63.2680)',
                'capacidad' => 10000,
                'unidadmedidaid' => $kgId,
                'tipoalmacenid' => $this->tiposAlmacen['agricola']->tipoalmacenid,
                'ambito' => AlmacenAmbito::AGRICOLA,
                'responsable_usuarioid' => $this->usuarios['jefe_agricola']->usuarioid,
                'activo' => true,
            ]
        );

        $this->almacenes['planta'] = Almacen::updateOrCreate(
            ['codigo' => 'ALM-PLT-01'],
            [
                'nombre' => 'Planta Procesadora Parque Industrial',
                'descripcion' => 'Almacén central de recepción de materias primas y despacho de productos terminados.',
                'ubicacion' => 'Parque Industrial Mz. 14, Santa Cruz (-17.7689, -63.1415)',
                'capacidad' => 30000,
                'unidadmedidaid' => $kgId,
                'tipoalmacenid' => $this->tiposAlmacen['planta']->tipoalmacenid,
                'ambito' => AlmacenAmbito::PLANTA,
                'responsable_usuarioid' => $this->usuarios['jefe_planta']->usuarioid,
                'activo' => true,
            ]
        );

        $this->almacenes['mayorista'] = Almacen::updateOrCreate(
            ['codigo' => 'ALM-MAY-01'],
            [
                'nombre' => 'Centro Mayorista Piraí',
                'descripcion' => 'Centro de distribución mayorista para abastecimiento a puntos de venta.',
                'ubicacion' => 'Av. Grigotá 3er Anillo, Mercado Piraí, Santa Cruz (-17.7962, -63.1950)',
                'capacidad' => 25000,
                'unidadmedidaid' => $kgId,
                'tipoalmacenid' => $this->tiposAlmacen['mayorista']->tipoalmacenid,
                'ambito' => AlmacenAmbito::MAYORISTA,
                'responsable_usuarioid' => $this->usuarios['jefe_mayorista']->usuarioid,
                'activo' => true,
            ]
        );

        // Asignar almacenid por defecto en usuarios clave
        $this->usuarios['jefe_agricola']->update(['almacenid' => $this->almacenes['agr_norte']->almacenid]);
        $this->usuarios['agricultor']->update(['almacenid' => $this->almacenes['agr_norte']->almacenid]);
        $this->usuarios['agricultor2']->update(['almacenid' => $this->almacenes['agr_valles']->almacenid]);
        $this->usuarios['jefe_planta']->update(['almacenid' => $this->almacenes['planta']->almacenid]);
        $this->usuarios['planta']->update(['almacenid' => $this->almacenes['planta']->almacenid]);
        $this->usuarios['jefe_mayorista']->update(['almacenid' => $this->almacenes['mayorista']->almacenid]);
        $this->usuarios['mayorista']->update(['almacenid' => $this->almacenes['mayorista']->almacenid]);

        // Puntos de venta y sus almacenes PDV
        $this->almacenes['pdv_alvaro'] = Almacen::updateOrCreate(
            ['codigo' => 'ALM-PDV-01'],
            [
                'nombre' => 'Almacén — Mercado Alvaro',
                'descripcion' => 'Inventario minorista del Punto de Venta Mercado Alvaro.',
                'ubicacion' => 'Av. Grigotá esq. Ñuflo de Chávez, Santa Cruz (-17.7892, -63.1811)',
                'capacidad' => 4000,
                'unidadmedidaid' => $kgId,
                'tipoalmacenid' => $this->tiposAlmacen['pdv']->tipoalmacenid,
                'ambito' => AlmacenAmbito::PUNTO_VENTA,
                'responsable_usuarioid' => $this->usuarios['minorista']->usuarioid,
                'activo' => true,
            ]
        );
        $this->puntosVenta['alvaro'] = PuntoVenta::updateOrCreate(
            ['nombre' => 'Mercado Alvaro'],
            [
                'usuarioid' => $this->usuarios['minorista']->usuarioid,
                'almacenid' => $this->almacenes['pdv_alvaro']->almacenid,
                'direccion' => 'Av. Grigotá esq. Ñuflo de Chávez, Santa Cruz',
                'latitud' => -17.7892,
                'longitud' => -63.1811,
                'activo' => true,
                'observaciones' => 'Punto de venta principal minorista con productos trazados por QR.',
                'fechacreacion' => now()->subDays(90),
            ]
        );

        $this->almacenes['pdv_norte'] = Almacen::updateOrCreate(
            ['codigo' => 'ALM-PDV-02'],
            [
                'nombre' => 'Almacén — Supermercado Norte',
                'descripcion' => 'Inventario minorista del Punto de Venta Supermercado Norte.',
                'ubicacion' => 'Av. Banzer 4to Anillo, Santa Cruz (-17.7460, -63.1755)',
                'capacidad' => 5000,
                'unidadmedidaid' => $kgId,
                'tipoalmacenid' => $this->tiposAlmacen['pdv']->tipoalmacenid,
                'ambito' => AlmacenAmbito::PUNTO_VENTA,
                'responsable_usuarioid' => $this->usuarios['minorista']->usuarioid,
                'activo' => true,
            ]
        );
        $this->puntosVenta['norte'] = PuntoVenta::updateOrCreate(
            ['nombre' => 'Supermercado Norte'],
            [
                'usuarioid' => $this->usuarios['minorista']->usuarioid,
                'almacenid' => $this->almacenes['pdv_norte']->almacenid,
                'direccion' => 'Av. Banzer 4to Anillo, Santa Cruz',
                'latitud' => -17.7460,
                'longitud' => -63.1755,
                'activo' => true,
                'observaciones' => 'Sucursal minorista Zona Norte.',
                'fechacreacion' => now()->subDays(60),
            ]
        );
        $this->usuarios['minorista']->update(['almacenid' => $this->almacenes['pdv_alvaro']->almacenid]);
    }

    private function seedInventarioInicialCampoYPlanta(): void
    {
        $kg = $this->unidades['kg']->unidadmedidaid;
        $l = $this->unidades['l']->unidadmedidaid;

        $tSiembra = $this->tiposInsumo['material de siembra']->tipoinsumoid;
        $tFert = $this->tiposInsumo['fertilizantes']->tipoinsumoid;
        $tPlaga = $this->tiposInsumo['control de plagas']->tipoinsumoid;
        $tProc = $this->tiposInsumo['insumo de procesamiento']->tipoinsumoid;

        $jefeAgr = $this->usuarios['jefe_agricola'];
        $jefePlt = $this->usuarios['jefe_planta'];

        $insumosAgrNorte = [
            'semilla_tomate' => ['nombre' => 'Semilla de Tomate Perita', 'tipo' => $tSiembra, 'um' => $kg, 'stock' => 500.0, 'min' => 30, 'precio' => 45.0, 'dosis' => 15, 'dosis_u' => 'kg', 'rend' => 750, 'desc' => 'Semilla certificada de tomate perita para campo abierto.'],
            'semilla_papa' => ['nombre' => 'Semilla de Papa Huaycha', 'tipo' => $tSiembra, 'um' => $kg, 'stock' => 780.0, 'min' => 50, 'precio' => 18.0, 'dosis' => 45, 'dosis_u' => 'kg', 'rend' => 800, 'desc' => 'Tubérculo-semilla certificada variedad Huaycha.'],
            'semilla_zanahoria' => ['nombre' => 'Semilla de Zanahoria Imperator', 'tipo' => $tSiembra, 'um' => $kg, 'stock' => 270.0, 'min' => 20, 'precio' => 55.0, 'dosis' => 12, 'dosis_u' => 'kg', 'rend' => 600, 'desc' => 'Semilla seleccionada de zanahoria Imperator.'],
            'fert_npk' => ['nombre' => 'Fertilizante AgroBoost NPK 15-15-15', 'tipo' => $tFert, 'um' => $kg, 'stock' => 1070.0, 'min' => 80, 'precio' => 12.5, 'dosis' => 35, 'dosis_u' => 'kg', 'rend' => null, 'desc' => 'Fertilizante balanceado granulado de liberación gradual.'],
            'fert_urea' => ['nombre' => 'Urea Granulada 46%', 'tipo' => $tFert, 'um' => $kg, 'stock' => 500.0, 'min' => 50, 'precio' => 9.8, 'dosis' => 30, 'dosis_u' => 'kg', 'rend' => null, 'desc' => 'Fuente concentrada de nitrógeno para desarrollo vegetativo.'],
            'plaga_neem' => ['nombre' => 'Bioinsecticida Neem Orgánico', 'tipo' => $tPlaga, 'um' => $l, 'stock' => 147.0, 'min' => 15, 'precio' => 38.0, 'dosis' => 4, 'dosis_u' => 'l', 'rend' => null, 'desc' => 'Control biológico de plagas de amplio espectro apto para trazabilidad.'],
            'plaga_cobre' => ['nombre' => 'Fungicida Cobre Hidróxido', 'tipo' => $tPlaga, 'um' => $kg, 'stock' => 90.0, 'min' => 10, 'precio' => 42.0, 'dosis' => 2.5, 'dosis_u' => 'kg', 'rend' => null, 'desc' => 'Fungicida preventivo para tizón y manchas foliares.'],
        ];

        $cajaCosechera = $this->tiposEmpaque['caja plástica cosechera'] ?? null;
        $sacoAgr = $this->tiposEmpaque['saco agrícola'] ?? null;

        foreach ($insumosAgrNorte as $key => $def) {
            $ins = Insumo::updateOrCreate(
                ['nombre' => $def['nombre'], 'almacenid' => $this->almacenes['agr_norte']->almacenid],
                [
                    'tipoinsumoid' => $def['tipo'],
                    'unidadmedidaid' => $def['um'],
                    'stock' => $def['stock'],
                    'stockminimo' => $def['min'],
                    'proveedor' => 'AgroInsumos Santa Cruz S.R.L.',
                    'preciounitario' => $def['precio'],
                    'descripcion' => $def['desc'],
                    'dosis_por_ha' => $def['dosis'],
                    'dosis_unidad' => $def['dosis_u'],
                    'rendimiento_cosecha_kg_ha' => $def['rend'],
                ]
            );
            $this->insumosCampo[$key] = $ins;

            $this->registrarMovimiento(
                $this->almacenes['agr_norte']->almacenid,
                $ins->insumoid,
                $this->tiposMovimiento['compra']->tipo_movimiento_almacenid,
                $jefeAgr->usuarioid,
                $def['um'],
                $def['stock'],
                0.0,
                $def['stock'],
                now()->subDays(90),
                'OC-AGR-'.str_pad((string) $ins->insumoid, 4, '0', STR_PAD_LEFT),
                'Ingreso por compra inicial de temporada agrícola'
            );

            // Catálogo de empaque cosecha para las semillas
            if ($key === 'semilla_tomate' && $cajaCosechera) {
                CatalogoTamanoConteo::updateOrCreate(
                    ['insumoid' => $ins->insumoid, 'nombre' => 'Caja cosechera 20 kg'],
                    ['conteo_por_empaque' => 20, 'peso_promedio_kg' => 1.0, 'tipoempaqueid' => $cajaCosechera->tipoempaqueid, 'activo' => true]
                );
            } elseif ($key === 'semilla_papa' && $sacoAgr) {
                CatalogoTamanoConteo::updateOrCreate(
                    ['insumoid' => $ins->insumoid, 'nombre' => 'Saco agrícola 50 kg'],
                    ['conteo_por_empaque' => 50, 'peso_promedio_kg' => 1.0, 'tipoempaqueid' => $sacoAgr->tipoempaqueid, 'activo' => true]
                );
            }
        }

        // Almacén Agrícola Valles
        $insumosValles = [
            ['nombre' => 'Semilla de Cebolla Roja', 'tipo' => $tSiembra, 'um' => $kg, 'stock' => 180.0, 'min' => 20, 'precio' => 48.0, 'desc' => 'Semilla seleccionada para zona de valles.'],
            ['nombre' => 'Compost Orgánico Premium', 'tipo' => $tFert, 'um' => $kg, 'stock' => 400.0, 'min' => 40, 'precio' => 6.5, 'desc' => 'Abono orgánico madurado para preparación de suelos.'],
        ];
        foreach ($insumosValles as $def) {
            $ins = Insumo::updateOrCreate(
                ['nombre' => $def['nombre'], 'almacenid' => $this->almacenes['agr_valles']->almacenid],
                [
                    'tipoinsumoid' => $def['tipo'],
                    'unidadmedidaid' => $def['um'],
                    'stock' => $def['stock'],
                    'stockminimo' => $def['min'],
                    'proveedor' => 'Valles Fértiles S.A.',
                    'preciounitario' => $def['precio'],
                    'descripcion' => $def['desc'],
                ]
            );
            $this->registrarMovimiento(
                $this->almacenes['agr_valles']->almacenid,
                $ins->insumoid,
                $this->tiposMovimiento['compra']->tipo_movimiento_almacenid,
                $jefeAgr->usuarioid,
                $def['um'],
                $def['stock'],
                0.0,
                $def['stock'],
                now()->subDays(85),
                'OC-VAL-'.str_pad((string) $ins->insumoid, 4, '0', STR_PAD_LEFT),
                'Compra inicial de insumos para Almacén Valles'
            );
        }

        // Insumos auxiliares de procesamiento en Planta
        $insumosPlanta = [
            ['nombre' => 'Aceite vegetal refinado', 'um' => $l, 'stock' => 400.0, 'min' => 50, 'precio' => 14.0, 'desc' => 'Aceite de girasol de grado alimenticio para fritura industrial.'],
            ['nombre' => 'Sal refinada industrial', 'um' => $kg, 'stock' => 250.0, 'min' => 30, 'precio' => 3.5, 'desc' => 'Sal fina yodada para salsas y snacks.'],
            ['nombre' => 'Vinagre blanco natural', 'um' => $l, 'stock' => 180.0, 'min' => 25, 'precio' => 8.0, 'desc' => 'Acidificante natural para conservación de salsas.'],
        ];
        foreach ($insumosPlanta as $def) {
            $ins = Insumo::updateOrCreate(
                ['nombre' => $def['nombre'], 'almacenid' => $this->almacenes['planta']->almacenid],
                [
                    'tipoinsumoid' => $tProc,
                    'unidadmedidaid' => $def['um'],
                    'stock' => $def['stock'],
                    'stockminimo' => $def['min'],
                    'proveedor' => 'Distribuidora Industrial del Oriente',
                    'preciounitario' => $def['precio'],
                    'descripcion' => $def['desc'],
                ]
            );
            $this->registrarMovimiento(
                $this->almacenes['planta']->almacenid,
                $ins->insumoid,
                $this->tiposMovimiento['compra']->tipo_movimiento_almacenid,
                $jefePlt->usuarioid,
                $def['um'],
                $def['stock'],
                0.0,
                $def['stock'],
                now()->subDays(60),
                'OC-PLT-'.str_pad((string) $ins->insumoid, 4, '0', STR_PAD_LEFT),
                'Stock base de insumos de procesamiento en planta'
            );
        }
    }

    /**
     * @param  array<string, mixed>  $cfg
     * @return array<string, mixed>
     */
    private function seedCadenaTrazabilidadCompleta(array $cfg): array
    {
        $kgId = $this->unidades['kg']->unidadmedidaid;
        $haId = $this->unidades['ha']->unidadmedidaid;
        $prioridadMedia = Prioridad::where('nombre', 'Media')->value('prioridadid');
        $estadoAplicadoId = EstadoLoteInsumo::where('nombre', 'Aplicado')->value('estadoloteinsumoid');
        $destinoPlantaId = DestinoProduccion::where('nombre', 'Planta procesadora')->value('destinoproduccionid');

        $jefeAgr = $this->usuarios['jefe_agricola'];
        $agricultor = $this->usuarios['agricultor'];
        $jefePlt = $this->usuarios['jefe_planta'];
        $operarioPlt = $this->usuarios['planta'];
        $jefeMay = $this->usuarios['jefe_mayorista'];
        $minorista = $this->usuarios['minorista'];
        $choferAgr = $this->usuarios[$cfg['chofer_agr']];
        $choferPlt = $this->usuarios['chofer_planta'];
        $choferMay = $this->usuarios['chofer_mayorista'];

        $almAgr = $this->almacenes['agr_norte'];
        $almPlt = $this->almacenes['planta'];
        $almMay = $this->almacenes['mayorista'];
        $punto = $this->puntosVenta['alvaro'];
        $almPdv = $this->almacenes['pdv_alvaro'];

        $t0 = Carbon::now()->subDays((int) $cfg['dias_inicio']);

        // ── ETAPA 1: PRODUCCIÓN AGRÍCOLA (CAMPO) ─────────────────────────────
        $semilla = $this->insumosCampo[$cfg['semilla_key']];
        $fert = $this->insumosCampo['fert_npk'];
        $plaga = $this->insumosCampo['plaga_neem'];

        $loteData = LoteDefaults::enrich([
            'nombre' => $cfg['lote_nombre'],
            'codigo_trazabilidad' => $cfg['lote_codigo'],
            'cultivoid' => $this->cultivos[$cfg['cultivo']]->cultivoid,
            'usuarioid' => $agricultor->usuarioid,
            'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('finalizado'),
            'superficie' => $cfg['superficie_ha'],
            'unidadsuperficieid' => $haId,
            'ubicacion' => $cfg['ubicacion'],
            'latitud' => $cfg['lat'],
            'longitud' => $cfg['lng'],
            'insumosemillaid' => $semilla->insumoid,
            'cantidad_semilla_planificada' => $cfg['semilla_kg'],
        ], false);

        $lote = Lote::create(array_merge($loteData, [
            'fechasiembra' => $t0->copy()->addDays(2),
            'fechacreacion' => $t0,
            'fechamodificacion' => $t0->copy()->addDays(56),
        ]));

        // Historial completo de estados del lote
        $estados = [
            ['slug' => 'planificado', 'offset' => 0, 'obs' => 'Lote planificado y asignado para temporada agrícola.'],
            ['slug' => 'sembrado', 'offset' => 2, 'obs' => 'Siembra ejecutada con semilla certificada.'],
            ['slug' => 'en_crecimiento', 'offset' => 18, 'obs' => 'Desarrollo vegetativo monitoreado con riego y fertilización.'],
            ['slug' => 'listo_para_cosecha', 'offset' => 48, 'obs' => 'Madurez fisiológica óptima verificada en campo.'],
            ['slug' => 'cosechado', 'offset' => 52, 'obs' => 'Cosecha ingresada al Almacén Agrícola Norte.'],
            ['slug' => 'certificado', 'offset' => 54, 'obs' => 'Certificación de calidad agrícola emitida.'],
            ['slug' => 'finalizado', 'offset' => 56, 'obs' => 'Lote cerrado con despacho hacia planta procesadora.'],
        ];
        foreach ($estados as $e) {
            HistorialEstadoLote::create([
                'loteid' => $lote->loteid,
                'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug($e['slug']),
                'fecha_cambio' => $t0->copy()->addDays($e['offset']),
                'observaciones' => $e['obs'],
                'usuarioid' => $jefeAgr->usuarioid,
            ]);
        }

        // Actividades de campo con consumos reales descontados del stock
        $tiposAct = TipoActividad::pluck('tipoactividadid', 'nombre');
        $acts = [
            ['orden' => 1, 'tipo' => 'Siembra', 'desc' => 'Siembra directa de '.$cfg['cultivo'], 'dia' => 2, 'insumo' => $semilla, 'cant' => $cfg['semilla_kg']],
            ['orden' => 2, 'tipo' => 'Riego', 'desc' => 'Riego tecnificado por goteo — fase inicial', 'dia' => 8, 'insumo' => null, 'cant' => null],
            ['orden' => 3, 'tipo' => 'Fertilización', 'desc' => 'Aplicación de fertilizante NPK balanceado', 'dia' => 20, 'insumo' => $fert, 'cant' => $cfg['fert_kg']],
            ['orden' => 4, 'tipo' => 'Control de plagas', 'desc' => 'Control preventivo con bioinsecticida orgánico', 'dia' => 35, 'insumo' => $plaga, 'cant' => $cfg['plaga_cant']],
            ['orden' => 5, 'tipo' => 'Cosecha', 'desc' => 'Cosecha y selección de '.$cfg['cultivo'].' en campo', 'dia' => 52, 'insumo' => null, 'cant' => null],
        ];
        foreach ($acts as $a) {
            $fecha = $t0->copy()->addDays($a['dia']);
            $actividad = Actividad::create([
                'loteid' => $lote->loteid,
                'usuarioid' => $jefeAgr->usuarioid,
                'usuarioid_ejecutor' => $agricultor->usuarioid,
                'tipoactividadid' => $tiposAct[$a['tipo']],
                'prioridadid' => $prioridadMedia,
                'descripcion' => $a['desc'],
                'fechainicio' => $fecha->copy()->setTime(7, 30),
                'fechafin' => $fecha->copy()->setTime(12, 0),
                'fecha_planificada' => $fecha->toDateString(),
                'orden_secuencia' => $a['orden'],
                'observaciones' => 'Actividad verificada y cerrada conforme a buenas prácticas agrícolas.',
            ]);

            if ($a['insumo'] !== null && $a['cant'] !== null) {
                /** @var Insumo $ins */
                $ins = $a['insumo'];
                $saldoAnt = (float) $ins->stock;
                $saldoPost = max(0.0, $saldoAnt - (float) $a['cant']);
                $ins->update(['stock' => $saldoPost]);

                LoteInsumo::create([
                    'loteid' => $lote->loteid,
                    'insumoid' => $ins->insumoid,
                    'actividadid' => $actividad->actividadid,
                    'usuarioid' => $agricultor->usuarioid,
                    'cantidadusada' => $a['cant'],
                    'fechauo' => $fecha,
                    'costototal' => round((float) $a['cant'] * (float) $ins->preciounitario, 2),
                    'estadoloteinsumoid' => $estadoAplicadoId,
                    'observaciones' => 'Consumo registrado al cierre de '.$a['tipo'],
                ]);

                $this->registrarMovimiento(
                    $almAgr->almacenid,
                    $ins->insumoid,
                    $this->tiposMovimiento['consumo_interno']->tipo_movimiento_almacenid,
                    $agricultor->usuarioid,
                    $ins->unidadmedidaid,
                    (float) $a['cant'],
                    $saldoAnt,
                    $saldoPost,
                    $fecha,
                    'ACT-'.$actividad->actividadid,
                    'Consumo en lote '.$lote->nombre.' ('.$a['tipo'].')'
                );
            }
        }

        // Cosecha + almacenamiento en almacén agrícola (queda remanente para demo en vivo!)
        $fechaCosecha = $t0->copy()->addDays(52);
        $produccion = Produccion::create([
            'loteid' => $lote->loteid,
            'cantidad' => $cfg['cosecha_kg'],
            'unidadmedidaid' => $kgId,
            'cantidad_base' => $cfg['cosecha_kg'],
            'fechacosecha' => $fechaCosecha->toDateString(),
            'destinoproduccionid' => $destinoPlantaId,
            'almacendestinoid' => $almAgr->almacenid,
            'observaciones' => 'Cosecha de primera calidad del lote '.$cfg['lote_codigo'],
        ]);

        $remanenteCosecha = max(0.0, (float) $cfg['cosecha_kg'] - (float) $cfg['envio_kg']);
        $pa = ProduccionAlmacenamiento::create([
            'produccionid' => $produccion->produccionid,
            'almacenid' => $almAgr->almacenid,
            'cantidad' => $remanenteCosecha,
            'unidadmedidaid' => $kgId,
            'temperatura' => 10.5,
            'humedad' => 76.0,
            'temperatura_min' => 6.0,
            'temperatura_max' => 14.0,
            'humedad_min' => 65.0,
            'humedad_max' => 85.0,
            'fechaentrada' => $fechaCosecha,
            'observaciones' => 'Cosecha inicial '.number_format($cfg['cosecha_kg'], 0).' kg (despachados '.number_format($cfg['envio_kg'], 0).' kg a planta; disponible '.number_format($remanenteCosecha, 0).' kg).',
        ]);

        CertificacionLote::create([
            'loteid' => $lote->loteid,
            'usuarioid' => $jefeAgr->usuarioid,
            'codigo_certificado' => $cfg['cert_codigo'],
            'resultado' => CertificacionLote::RAZON_CERTIFICADO,
            'observaciones' => 'Lote cumple parámetros sanitarios, de inocuidad y trazabilidad de campo.',
            'recomendaciones' => 'Mantener ventilación y temperatura controlada durante el traslado a planta.',
            'fecha_certificacion' => $t0->copy()->addDays(54),
            'blockchain_estado' => 'confirmado',
            'blockchain_hash' => hash('sha256', $cfg['lote_codigo'].'|'.$cfg['cert_codigo']),
        ]);

        // ── ETAPA 2: ENVÍO AGRÍCOLA → PLANTA PROCESADORA ─────────────────────
        $fechaEnvio = $t0->copy()->addDays(56);
        $vehAgr = $this->vehiculos[$cfg['vehiculo_agr']];

        $pedidoAgr = Pedido::create([
            'numero_solicitud' => $cfg['pedido_num'],
            'nombre_planta' => $almPlt->nombre,
            'origen_latitud' => $cfg['lat'],
            'origen_longitud' => $cfg['lng'],
            'origen_direccion' => $almAgr->nombre.' · '.$almAgr->ubicacion,
            'latitud' => -17.7689,
            'longitud' => -63.1415,
            'direccion_texto' => $almPlt->ubicacion,
            'estado' => PedidoCatalogo::ESTADO_CONFIRMADO,
            'fechapedido' => $fechaEnvio,
            'fechaEntregaDeseada' => $fechaEnvio->copy()->addDay()->toDateString(),
            'hora_recogida' => '08:00',
            'hora_entrega_estimada' => '11:30',
            'creado_por_usuarioid' => $jefeAgr->usuarioid,
            'aceptado_por_usuarioid' => $jefeAgr->usuarioid,
            'fecha_aceptacion_agricola' => $fechaEnvio->copy()->setTime(7, 30),
            'observaciones' => 'Envío de materia prima '.$cfg['cultivo'].' — lote '.$cfg['lote_codigo'],
        ]);

        // Insumo materia prima en planta + MateriaPrimaLote
        $insMpPlanta = Insumo::create([
            'nombre' => $cfg['mp_nombre'],
            'tipoinsumoid' => $this->tiposInsumo['materia prima']->tipoinsumoid,
            'unidadmedidaid' => $kgId,
            'stock' => max(0.0, (float) $cfg['envio_kg'] - (float) $cfg['mp_usada_kg']),
            'stockminimo' => 100,
            'proveedor' => $almAgr->nombre,
            'preciounitario' => 5.5,
            'descripcion' => 'Materia prima recibida de campo — origen lote '.$cfg['lote_codigo'].' ('.$cfg['pedido_num'].').',
            'almacenid' => $almPlt->almacenid,
        ]);

        $detallePedido = DetallePedido::create([
            'pedidoid' => $pedidoAgr->pedidoid,
            'produccionalmacenamientoid' => $pa->produccionalmacenamientoid,
            'insumoid' => $insMpPlanta->insumoid,
            'producto_ref' => 'cosecha:'.$pa->produccionalmacenamientoid,
            'cultivo_personalizado' => $cfg['cultivo'].' fresco ('.$cfg['lote_nombre'].')',
            'cantidad' => $cfg['envio_kg'],
            'observaciones' => 'Despacho desde '.$almAgr->nombre.' · lote '.$cfg['lote_codigo'],
        ]);

        $estadoRecibidoCatId = DB::table('estado_asignacion_multiple_catalogo')->where('nombre', 'recibido_planta')->value('estadoasignacioncatalogoid');
        $envio = EnvioAsignacionMultiple::create([
            'externo_envio_id' => $cfg['envio_ext'],
            'pedidoid' => $pedidoAgr->pedidoid,
            'transportista_usuarioid' => $choferAgr->usuarioid,
            'asignadopor_usuarioid' => $jefeAgr->usuarioid,
            'vehiculo_ref' => $vehAgr->placa.' · '.$vehAgr->marca.' '.$vehAgr->modelo,
            'estado' => 'recibido_planta',
            'estadoasignacioncatalogoid' => $estadoRecibidoCatId,
            'tipotransporteid' => $this->tiposTransporte['REFRIGERADO']->tipotransporteid,
            'almacenid' => $almAgr->almacenid,
            'costo_bs' => 420.0,
            'fecha_asignacion' => $fechaEnvio->copy()->setTime(7, 45),
            'simulacion_inicio_at' => $fechaEnvio->copy()->setTime(8, 15),
            'simulacion_duracion_seg' => 10800,
            'llegada_confirmada_at' => $fechaEnvio->copy()->setTime(11, 15),
            'llegada_confirmada_usuarioid' => $choferAgr->usuarioid,
            'fecha_recepcion_planta' => $fechaEnvio->copy()->setTime(11, 45),
            'recepcion_usuarioid' => $jefePlt->usuarioid,
        ]);

        ChecklistCondicionLogistica::create([
            'envioasignacionmultipleid' => $envio->envioasignacionmultipleid,
            'almacenid' => $almPlt->almacenid,
            'revisado_por_usuarioid' => $jefePlt->usuarioid,
            'estado_general' => 'conforme',
            'productos_completos' => true,
            'empaque_intacto' => true,
            'temperatura_adecuada' => true,
            'sin_danos_visibles' => true,
            'documentacion_completa' => true,
            'observaciones' => 'Recepción sin novedades; mercadería conforme en peso y calidad.',
            'fecha_revision' => $fechaEnvio->copy()->setTime(11, 40),
        ]);

        FirmaTransportistaEnvio::create([
            'envioasignacionmultipleid' => $envio->envioasignacionmultipleid,
            'nombrefirmante' => $choferAgr->nombre.' '.$choferAgr->apellido,
            'firmante_usuarioid' => $choferAgr->usuarioid,
            'imagenfirma' => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
            'fechafirma' => $fechaEnvio->copy()->setTime(11, 20),
        ]);
        FirmaRecepcionEnvio::create([
            'envioasignacionmultipleid' => $envio->envioasignacionmultipleid,
            'nombrefirmante' => $jefePlt->nombre.' '.$jefePlt->apellido,
            'firmante_usuarioid' => $jefePlt->usuarioid,
            'imagenfirma' => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
            'fechafirma' => $fechaEnvio->copy()->setTime(11, 45),
        ]);

        $mpLote = MateriaPrimaLote::create([
            'insumoid' => $insMpPlanta->insumoid,
            'almacenid' => $almPlt->almacenid,
            'detallepedidoid' => $detallePedido->detallepedidoid,
            'lote_proveedor' => $cfg['mp_lote_codigo'],
            'numero_factura' => $cfg['envio_ext'],
            'fecha_recepcion' => $fechaEnvio->toDateString(),
            'fecha_vencimiento' => $fechaEnvio->copy()->addDays(25)->toDateString(),
            'cantidad' => $cfg['envio_kg'],
            'cantidad_disponible' => max(0.0, (float) $cfg['envio_kg'] - (float) $cfg['mp_usada_kg']),
            'conformidad_recepcion' => 'conforme',
            'observaciones' => 'Materia prima proveniente del lote agrícola '.$cfg['lote_codigo'],
        ]);
        $detallePedido->update(['materiaprimaloteid' => $mpLote->materiaprimaloteid]);

        $this->registrarMovimiento(
            $almPlt->almacenid,
            $insMpPlanta->insumoid,
            $this->tiposMovimiento['produccion_recibida']->tipo_movimiento_almacenid,
            $jefePlt->usuarioid,
            $kgId,
            (float) $cfg['envio_kg'],
            0.0,
            (float) $cfg['envio_kg'],
            $fechaEnvio,
            $cfg['envio_ext'],
            '[Recepción planta] Materia prima lote '.$cfg['lote_codigo'],
            ['materiaprimaloteid' => $mpLote->materiaprimaloteid]
        );

        // ── ETAPA 3: PROCESAMIENTO EN PLANTA ─────────────────────────────────
        $fechaPlanta = $t0->copy()->addDays(58)->setTime(8, 0);
        $plantilla = PlantillaTransformacion::with(['pasos.proceso', 'pasos.maquina', 'pasos.variables.variableEstandar'])
            ->where('nombre', $cfg['plantilla_nombre'])
            ->firstOrFail();

        $kgProducidos = round((float) $cfg['unidades_producidas'] * (float) $cfg['peso_neto_kg'], 2);

        $lotePlanta = LoteProduccionPedido::create([
            'pedidoid' => $pedidoAgr->pedidoid,
            'codigo_lote' => $cfg['lote_planta_codigo'],
            'nombre' => $cfg['producto_nombre'],
            'producto' => $cfg['producto_nombre'],
            'plantillatransformacionid' => $plantilla->plantillatransformacionid,
            'procesoplantaid' => $plantilla->pasos->first()?->procesoplantaid,
            'fecha_creacion' => $fechaPlanta->toDateString(),
            'hora_inicio' => $fechaPlanta,
            'hora_fin' => $fechaPlanta->copy()->addHours(count($plantilla->pasos) * 2),
            'cantidad_objetivo' => $kgProducidos,
            'cantidad_producida' => $kgProducidos,
            'unidadmedidaid' => $kgId,
            'empaque_catalogo_slug' => $cfg['empaque_slug'],
            'empaque_nombre_personalizado' => $cfg['presentacion_nombre'],
            'empaque_peso_neto_kg' => $cfg['peso_neto_kg'],
            'empaque_tipo_envase' => $cfg['tipo_envase'],
            'modo_planificacion' => EmpaquePlantaCatalogo::MODO_EMPAQUES,
            'cantidad_empaques_objetivo' => $cfg['unidades_producidas'],
            'observaciones' => 'Transformación industrial desde lote agrícola '.$cfg['lote_codigo'],
        ]);

        // Consumo de materia prima en planta
        $movConsumoMp = $this->registrarMovimiento(
            $almPlt->almacenid,
            $insMpPlanta->insumoid,
            $this->tiposMovimiento['consumo_interno']->tipo_movimiento_almacenid,
            $operarioPlt->usuarioid,
            $kgId,
            (float) $cfg['mp_usada_kg'],
            (float) $cfg['envio_kg'],
            max(0.0, (float) $cfg['envio_kg'] - (float) $cfg['mp_usada_kg']),
            $fechaPlanta,
            $cfg['lote_planta_codigo'],
            'Consumo de materia prima para lote '.$cfg['lote_planta_codigo'],
            [
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'materiaprimaloteid' => $mpLote->materiaprimaloteid,
            ]
        );

        LoteProduccionMateriaPrima::create([
            'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
            'materiaprimaloteid' => $mpLote->materiaprimaloteid,
            'insumoid' => $insMpPlanta->insumoid,
            'cantidad_planificada' => $cfg['mp_usada_kg'],
            'cantidad_usada' => $cfg['mp_usada_kg'],
            'almacen_movimientoid' => $movConsumoMp->almacen_movimientoid,
        ]);

        // Pasos de ruta, asignaciones y registros con variables dentro de rango
        foreach ($plantilla->pasos->sortBy('orden') as $idx => $paso) {
            $rutaPasoId = DB::table('lote_produccion_ruta_paso')->insertGetId([
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'orden' => $paso->orden,
                'procesoplantaid' => $paso->procesoplantaid,
                'maquinaplantaid' => $paso->maquinaplantaid,
                'notas' => $paso->notas,
                'plantillapasoid' => $paso->plantillapasoid,
                'created_at' => $fechaPlanta,
                'updated_at' => $fechaPlanta,
            ]);

            $pm = ProcesoMaquinaPlanta::firstOrCreate(
                [
                    'procesoplantaid' => $paso->procesoplantaid,
                    'maquinaplantaid' => $paso->maquinaplantaid,
                ],
                [
                    'orden_paso' => $paso->orden,
                    'nombre' => $paso->proceso?->nombre ?? 'Etapa '.$paso->orden,
                    'descripcion' => $paso->notas ?? 'Etapa de transformación',
                    'tiempo_estimado' => 90,
                ]
            );

            $vars = [];
            foreach ($paso->variables as $pv) {
                $cod = $pv->variableEstandar?->codigo ?? ('VAR-'.$pv->variableestandarid);
                $vars[$cod] = round(((float) $pv->valor_minimo + (float) $pv->valor_maximo) / 2, 2);
            }
            if ($vars === []) {
                $vars = ['estado' => 'conforme'];
            }

            $hIni = $fechaPlanta->copy()->addHours($idx * 2);
            $hFin = $hIni->copy()->addMinutes(95);

            $reg = RegistroProcesoMaquinaPlanta::create([
                'procesomaquinaplantaid' => $pm->procesomaquinaplantaid,
                'loteid' => $lote->loteid,
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'usuarioid' => $operarioPlt->usuarioid,
                'variables_ingresadas' => json_encode($vars, JSON_UNESCAPED_UNICODE),
                'cumple_estandar' => true,
                'observaciones' => ($paso->notas ?: $paso->proceso?->nombre).' completado dentro de parámetros estándar.',
                'hora_inicio' => $hIni,
                'hora_fin' => $hFin,
                'fecha_registro' => $hFin,
            ]);

            DB::table('asignacion_etapa_planta')->insert([
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'procesoplantaid' => $paso->procesoplantaid,
                'maquinaplantaid' => $paso->maquinaplantaid,
                'operador_usuarioid' => $operarioPlt->usuarioid,
                'asignado_por_usuarioid' => $jefePlt->usuarioid,
                'estado' => 'completada',
                'observaciones' => 'Etapa ejecutada conforme a ficha técnica.',
                'registroprocesomaquinaplantaid' => $reg->registroprocesomaquinaplantaid,
                'creado_en' => $fechaPlanta,
                'completada_en' => $hFin,
                'loteproduccionrutapasoid' => $rutaPasoId,
                'orden' => $paso->orden,
            ]);
        }

        // Evaluación final de calidad en planta
        $fechaEval = $fechaPlanta->copy()->addHours(count($plantilla->pasos) * 2 + 1);
        EvaluacionFinalLoteProduccion::create([
            'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
            'inspector_usuarioid' => $jefePlt->usuarioid,
            'razon' => EvaluacionFinalLoteProduccion::RAZON_CERTIFICADO,
            'codigo_certificado' => $cfg['cert_planta_codigo'],
            'observaciones' => 'Lote conforme en inocuidad, sellado, peso neto y trazabilidad completa.',
            'recomendaciones' => 'Apto para despacho a centro mayorista.',
            'fecha_evaluacion' => $fechaEval,
        ]);

        // Producto terminado en Planta + Presentación + InventarioPresentacionLote
        $kgMayorista = round((float) $cfg['unidades_mayorista'] * (float) $cfg['peso_neto_kg'], 2);
        $unidadesRestantesPlanta = (int) $cfg['unidades_producidas'] - (int) $cfg['unidades_mayorista'];
        $kgRestantesPlanta = round($unidadesRestantesPlanta * (float) $cfg['peso_neto_kg'], 2);

        $insProdPlanta = Insumo::create([
            'nombre' => $cfg['producto_nombre'],
            'tipoinsumoid' => $this->tiposInsumo['producto terminado']->tipoinsumoid,
            'unidadmedidaid' => $kgId,
            'stock' => $kgRestantesPlanta,
            'stockminimo' => 50,
            'proveedor' => $almPlt->nombre,
            'preciounitario' => 28.0,
            'descripcion' => 'Producto terminado en planta — origen lote agrícola '.$cfg['lote_codigo'].' / lote planta '.$cfg['lote_planta_codigo'].'.',
            'almacenid' => $almPlt->almacenid,
        ]);

        $tipoEmpaquePlanta = $this->tiposEmpaque[mb_strtolower($cfg['tipo_envase'] === 'frasco' ? 'Frasco' : 'Bolsa plástica')] ?? null;
        $presPlanta = InsumoPresentacion::create([
            'insumoid' => $insProdPlanta->insumoid,
            'tipoempaqueid' => $tipoEmpaquePlanta?->tipoempaqueid,
            'nombre' => $cfg['presentacion_nombre'],
            'tipo_envase' => $cfg['tipo_envase'],
            'peso_neto_kg' => $cfg['peso_neto_kg'],
            'unidades_por_caja' => 12,
            'orden' => 1,
            'activo' => true,
            'sku' => $cfg['sku'],
        ]);
        $lotePlanta->update(['insumo_presentacionid' => $presPlanta->insumo_presentacionid]);

        $invPresPlanta = InventarioPresentacionLote::create([
            'almacenid' => $almPlt->almacenid,
            'insumoid' => $insProdPlanta->insumoid,
            'insumo_presentacionid' => $presPlanta->insumo_presentacionid,
            'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
            'referencia_lote' => $cfg['lote_planta_codigo'],
            'cantidad_unidades' => $unidadesRestantesPlanta,
            'cantidad_kg' => $kgRestantesPlanta,
            'fecha_vencimiento' => $fechaEval->copy()->addMonths(10)->toDateString(),
        ]);

        AlmacenajeLoteProduccion::create([
            'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
            'almacenid' => $almPlt->almacenid,
            'insumoid' => $insProdPlanta->insumoid,
            'insumo_presentacionid' => $presPlanta->insumo_presentacionid,
            'inventario_presentacion_loteid' => $invPresPlanta->inventario_presentacion_loteid,
            'ubicacion' => 'Rack PT-A1 · Cámara de producto terminado',
            'condicion' => 'Óptima',
            'cantidad' => $kgProducidos,
            'latitud_recojo' => -17.7689,
            'longitud_recojo' => -63.1415,
            'direccion_recojo' => $almPlt->ubicacion,
            'observaciones' => 'Ingreso certificado de '.$cfg['unidades_producidas'].' unidades ('.$kgProducidos.' kg).',
            'fecha_almacenaje' => $fechaEval->copy()->addHour(),
        ]);

        $this->registrarMovimiento(
            $almPlt->almacenid,
            $insProdPlanta->insumoid,
            $this->tiposMovimiento['produccion_recibida']->tipo_movimiento_almacenid,
            $jefePlt->usuarioid,
            $kgId,
            $kgProducidos,
            0.0,
            $kgProducidos,
            $fechaEval->copy()->addHour(),
            $cfg['lote_planta_codigo'],
            '[Ingreso producto terminado] Lote '.$cfg['lote_planta_codigo'],
            [
                'insumo_presentacionid' => $presPlanta->insumo_presentacionid,
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'cantidad_unidades' => $cfg['unidades_producidas'],
                'inventario_presentacion_loteid' => $invPresPlanta->inventario_presentacion_loteid,
            ]
        );

        // ── ETAPA 4: TRASLADO PLANTA → CENTRO MAYORISTA ──────────────────────
        $fechaTraslado = $t0->copy()->addDays(63);
        $vehPlt = $this->vehiculos['SCZ-PLT-01'];

        $rutaPm = RutaDistribucion::create([
            'codigo' => $cfg['ruta_pm_codigo'],
            'nombre' => 'Traslado '.$cfg['producto_nombre'].' → '.$almMay->nombre,
            'tipo_ruta' => RutaDistribucionCatalogo::TIPO_RUTA_PLANTA_MAYORISTA,
            'almacen_planta_origenid' => $almPlt->almacenid,
            'almacen_mayorista_destinoid' => $almMay->almacenid,
            'transportista_usuarioid' => $choferPlt->usuarioid,
            'vehiculoid' => $vehPlt->vehiculoid,
            'creado_por_usuarioid' => $jefePlt->usuarioid,
            'estado' => RutaDistribucionCatalogo::ESTADO_COMPLETADA,
            'fecha_salida' => $fechaTraslado->copy()->setTime(9, 0),
            'simulacion_inicio_at' => $fechaTraslado->copy()->setTime(9, 10),
            'simulacion_duracion_seg' => 5400,
            'llegada_confirmada_at' => $fechaTraslado->copy()->setTime(10, 45),
            'llegada_confirmada_usuarioid' => $choferPlt->usuarioid,
            'fecha_aprobacion_mayorista' => $fechaTraslado->copy()->setTime(11, 15),
            'aprobado_por_usuarioid' => $jefeMay->usuarioid,
            'costo_bs' => 310.0,
        ]);

        RutaDistribucionParada::create([
            'rutadistribucionid' => $rutaPm->rutadistribucionid,
            'orden' => 1,
            'tipo' => RutaDistribucionCatalogo::PARADA_CARGA_PLANTA,
            'almacenid' => $almPlt->almacenid,
            'destino' => $almPlt->nombre,
            'latitud' => -17.7689,
            'longitud' => -63.1415,
            'estado' => 'completada',
        ]);
        RutaDistribucionParada::create([
            'rutadistribucionid' => $rutaPm->rutadistribucionid,
            'orden' => 2,
            'tipo' => RutaDistribucionCatalogo::PARADA_ENTREGA_MAYORISTA,
            'almacenid' => $almMay->almacenid,
            'destino' => $almMay->nombre,
            'latitud' => -17.7962,
            'longitud' => -63.1950,
            'estado' => 'completada',
        ]);

        DetalleTrasladoPlantaMayorista::create([
            'rutadistribucionid' => $rutaPm->rutadistribucionid,
            'insumoid' => $insProdPlanta->insumoid,
            'insumo_presentacionid' => $presPlanta->insumo_presentacionid,
            'inventario_presentacion_loteid' => $invPresPlanta->inventario_presentacion_loteid,
            'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
            'presentacion_nombre' => $cfg['presentacion_nombre'],
            'producto_nombre' => $cfg['producto_nombre'],
            'cantidad' => $kgMayorista,
            'cantidad_recibida' => $kgMayorista,
            'cantidad_unidades' => $cfg['unidades_mayorista'],
            'observaciones' => 'Traslado certificado hacia Centro Mayorista Piraí.',
        ]);

        // Egreso en Planta
        $this->registrarMovimiento(
            $almPlt->almacenid,
            $insProdPlanta->insumoid,
            $this->tiposMovimiento['envio']->tipo_movimiento_almacenid,
            $jefePlt->usuarioid,
            $kgId,
            $kgMayorista,
            $kgProducidos,
            $kgRestantesPlanta,
            $fechaTraslado,
            $cfg['ruta_pm_codigo'],
            '[Traslado planta → mayorista salida] '.$cfg['producto_nombre'].' · '.$cfg['ruta_pm_codigo'],
            [
                'insumo_presentacionid' => $presPlanta->insumo_presentacionid,
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'cantidad_unidades' => $cfg['unidades_mayorista'],
                'inventario_presentacion_loteid' => $invPresPlanta->inventario_presentacion_loteid,
            ]
        );

        // Stock en Centro Mayorista Piraí (descontando lo enviado al PDV)
        $kgPdv = round((float) $cfg['unidades_pdv'] * (float) $cfg['peso_neto_kg'], 2);
        $unidadesRestantesMay = (int) $cfg['unidades_mayorista'] - (int) $cfg['unidades_pdv'];
        $kgRestantesMay = round($unidadesRestantesMay * (float) $cfg['peso_neto_kg'], 2);

        $insProdMay = Insumo::create([
            'nombre' => $cfg['producto_nombre'],
            'tipoinsumoid' => $this->tiposInsumo['producto terminado']->tipoinsumoid,
            'unidadmedidaid' => $kgId,
            'stock' => $kgRestantesMay,
            'stockminimo' => 40,
            'proveedor' => $almPlt->nombre,
            'preciounitario' => 32.0,
            'descripcion' => 'Stock mayorista certificado — origen lote agrícola '.$cfg['lote_codigo'].' / lote planta '.$cfg['lote_planta_codigo'].'.',
            'almacenid' => $almMay->almacenid,
        ]);

        $presMay = InsumoPresentacion::create([
            'insumoid' => $insProdMay->insumoid,
            'tipoempaqueid' => $tipoEmpaquePlanta?->tipoempaqueid,
            'nombre' => $cfg['presentacion_nombre'],
            'tipo_envase' => $cfg['tipo_envase'],
            'peso_neto_kg' => $cfg['peso_neto_kg'],
            'unidades_por_caja' => 12,
            'orden' => 1,
            'activo' => true,
            'sku' => $cfg['sku'].'-MAY',
        ]);

        $invPresMay = InventarioPresentacionLote::create([
            'almacenid' => $almMay->almacenid,
            'insumoid' => $insProdMay->insumoid,
            'insumo_presentacionid' => $presMay->insumo_presentacionid,
            'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
            'referencia_lote' => $cfg['lote_planta_codigo'],
            'cantidad_unidades' => $unidadesRestantesMay,
            'cantidad_kg' => $kgRestantesMay,
            'fecha_vencimiento' => $fechaEval->copy()->addMonths(10)->toDateString(),
        ]);

        // Ingreso en Mayorista
        $this->registrarMovimiento(
            $almMay->almacenid,
            $insProdMay->insumoid,
            $this->tiposMovimiento['produccion_recibida']->tipo_movimiento_almacenid,
            $jefeMay->usuarioid,
            $kgId,
            $kgMayorista,
            0.0,
            $kgMayorista,
            $fechaTraslado,
            $cfg['ruta_pm_codigo'],
            '[Traslado planta → mayorista ingreso] '.$cfg['producto_nombre'].' · '.$cfg['ruta_pm_codigo'],
            [
                'insumo_presentacionid' => $presMay->insumo_presentacionid,
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'cantidad_unidades' => $cfg['unidades_mayorista'],
                'inventario_presentacion_loteid' => $invPresMay->inventario_presentacion_loteid,
            ]
        );

        // ── ETAPA 5: DISTRIBUCIÓN MAYORISTA → PDV Y QR PÚBLICO ───────────────
        $fechaPdv = $t0->copy()->addDays(68);
        $vehMay = $this->vehiculos['SCZ-MAY-01'];

        $rutaPdv = RutaDistribucion::create([
            'codigo' => $cfg['ruta_pdv_codigo'],
            'nombre' => 'Distribución '.$almMay->nombre.' → '.$punto->nombre,
            'tipo_ruta' => RutaDistribucionCatalogo::TIPO_RUTA_MAYORISTA_PDV,
            'almacen_planta_origenid' => $almPlt->almacenid,
            'almacen_mayorista_origenid' => $almMay->almacenid,
            'transportista_usuarioid' => $choferMay->usuarioid,
            'vehiculoid' => $vehMay->vehiculoid,
            'creado_por_usuarioid' => $jefeMay->usuarioid,
            'estado' => RutaDistribucionCatalogo::ESTADO_COMPLETADA,
            'fecha_salida' => $fechaPdv->copy()->addDay()->setTime(8, 30),
            'simulacion_inicio_at' => $fechaPdv->copy()->addDay()->setTime(8, 35),
            'simulacion_duracion_seg' => 2700,
            'llegada_confirmada_at' => $fechaPdv->copy()->addDay()->setTime(9, 25),
            'llegada_confirmada_usuarioid' => $choferMay->usuarioid,
            'costo_bs' => 140.0,
        ]);

        $productoPdvNombre = $cfg['producto_nombre'].' · '.$cfg['presentacion_nombre'];

        $pedidoPdv = PedidoDistribucion::create([
            'numero_solicitud' => $cfg['pedido_pdv_num'],
            'puntoventaid' => $punto->puntoventaid,
            'almacen_planta_origenid' => $almPlt->almacenid,
            'almacen_mayorista_origenid' => $almMay->almacenid,
            'rutadistribucionid' => $rutaPdv->rutadistribucionid,
            'transportista_usuarioid' => $choferMay->usuarioid,
            'vehiculoid' => $vehMay->vehiculoid,
            'estado' => PedidoDistribucionCatalogo::ESTADO_RECIBIDO,
            'tipo_solicitud' => PedidoDistribucionCatalogo::TIPO_SOLICITUD_STOCK,
            'canal_origen' => PedidoDistribucionCatalogo::CANAL_SISTEMA,
            'fechapedido' => $fechaPdv->copy()->setTime(10, 0),
            'fecha_entrega_deseada' => $fechaPdv->copy()->addDay()->toDateString(),
            'hora_entrega_deseada' => '10:00',
            'fecha_aceptacion' => $fechaPdv->copy()->setTime(11, 30),
            'fecha_envio' => $fechaPdv->copy()->addDay()->setTime(8, 30),
            'fecha_recepcion' => $fechaPdv->copy()->addDay()->setTime(9, 40),
            'fecha_confirmacion_minorista' => $fechaPdv->copy()->addDay()->setTime(9, 45),
            'creado_por_usuarioid' => $minorista->usuarioid,
            'aceptado_por_usuarioid' => $jefeMay->usuarioid,
            'observaciones' => 'Pedido de distribución trazado — lote agrícola '.$cfg['lote_codigo'],
        ]);

        RutaDistribucionParada::create([
            'rutadistribucionid' => $rutaPdv->rutadistribucionid,
            'orden' => 1,
            'tipo' => RutaDistribucionCatalogo::PARADA_CARGA_MAYORISTA,
            'almacenid' => $almMay->almacenid,
            'destino' => $almMay->nombre,
            'latitud' => -17.7962,
            'longitud' => -63.1950,
            'estado' => 'completada',
        ]);
        RutaDistribucionParada::create([
            'rutadistribucionid' => $rutaPdv->rutadistribucionid,
            'orden' => 2,
            'tipo' => RutaDistribucionCatalogo::PARADA_ENTREGA_PDV,
            'puntoventaid' => $punto->puntoventaid,
            'pedidodistribucionid' => $pedidoPdv->pedidodistribucionid,
            'destino' => $punto->nombre,
            'latitud' => $punto->latitud,
            'longitud' => $punto->longitud,
            'estado' => 'completada',
        ]);

        $detPdv = DetallePedidoDistribucion::create([
            'pedidodistribucionid' => $pedidoPdv->pedidodistribucionid,
            'insumoid' => $insProdMay->insumoid,
            'insumo_planta_referenciaid' => $insProdPlanta->insumoid,
            'insumo_presentacionid' => $presMay->insumo_presentacionid,
            'almacen_mayorista_origenid' => $almMay->almacenid,
            'inventario_presentacion_loteid' => $invPresMay->inventario_presentacion_loteid,
            'referencia_lote' => $cfg['lote_planta_codigo'],
            'producto_nombre' => $productoPdvNombre,
            'tipo_envase' => $cfg['tipo_envase'],
            'cantidad' => $cfg['unidades_pdv'],
            'observaciones' => $cfg['unidades_pdv'].' unidades ('.$kgPdv.' kg) — lote '.$cfg['lote_codigo'],
        ]);

        // Egreso en Mayorista
        $this->registrarMovimiento(
            $almMay->almacenid,
            $insProdMay->insumoid,
            $this->tiposMovimiento['despacho']->tipo_movimiento_almacenid,
            $jefeMay->usuarioid,
            $kgId,
            $kgPdv,
            $kgMayorista,
            $kgRestantesMay,
            $fechaPdv->copy()->addDay(),
            $cfg['pedido_pdv_num'],
            'Despacho mayorista hacia '.$punto->nombre.' ('.$cfg['pedido_pdv_num'].')',
            [
                'insumo_presentacionid' => $presMay->insumo_presentacionid,
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'cantidad_unidades' => $cfg['unidades_pdv'],
                'detallepedidodistribucionid' => $detPdv->detallepedidodistribucionid,
                'inventario_presentacion_loteid' => $invPresMay->inventario_presentacion_loteid,
            ]
        );

        // Inventario final en Punto de Venta con Código QR público
        $insumoPdv = Insumo::create([
            'nombre' => $productoPdvNombre,
            'tipoinsumoid' => $this->tiposInsumo['producto terminado']->tipoinsumoid,
            'unidadmedidaid' => $kgId,
            'stock' => $kgPdv,
            'stockminimo' => 15,
            'proveedor' => $almMay->nombre,
            'preciounitario' => 38.0,
            'descripcion' => 'Producto con trazabilidad completa desde campo — lote '.$cfg['lote_codigo'].' · '.$cfg['pedido_pdv_num'],
            'almacenid' => $almPdv->almacenid,
            'codigo_trazabilidad' => $cfg['qr_codigo'],
        ]);

        $this->registrarMovimiento(
            $almPdv->almacenid,
            $insumoPdv->insumoid,
            $this->tiposMovimiento['produccion_recibida']->tipo_movimiento_almacenid,
            $minorista->usuarioid,
            $kgId,
            $kgPdv,
            0.0,
            $kgPdv,
            $fechaPdv->copy()->addDay(),
            $cfg['pedido_pdv_num'],
            '[Recepción PDV] '.$cfg['pedido_pdv_num'].' · '.$cfg['unidades_pdv'].' unidades ('.$kgPdv.' kg)',
            [
                'loteproduccionpedidoid' => $lotePlanta->loteproduccionpedidoid,
                'cantidad_unidades' => $cfg['unidades_pdv'],
            ]
        );

        return [
            'lote' => $lote,
            'pa' => $pa,
            'pedido_agr' => $pedidoAgr,
            'ins_mp_planta' => $insMpPlanta,
            'mp_lote' => $mpLote,
            'ins_prod_may' => $insProdMay,
            'pres_may' => $presMay,
            'inv_pres_may' => $invPresMay,
            'ins_prod_planta' => $insProdPlanta,
            'insumo_pdv' => $insumoPdv,
        ];
    }

    /**
     * Escenarios activos listos para operar en vivo durante una presentación:
     * 1) Lote de Zanahoria en crecimiento con 2 actividades pendientes en Mobile/Web.
     * 2) Envío agrícola pendiente de asignación desde Almacén Agrícola Norte a Planta.
     * 3) Lote de planta en ejecución con etapa pendiente asignada a planta@agrofusion.com.
     * 4) Pedido minorista pendiente para Supermercado Norte listo para aprobar por mayorista.
     *
     * @param  array<string, mixed>  $cadenaTomate
     */
    private function seedEscenariosActivosDemo(array $cadenaTomate): void
    {
        $kgId = $this->unidades['kg']->unidadmedidaid;
        $haId = $this->unidades['ha']->unidadmedidaid;
        $prioridadAlta = Prioridad::where('nombre', 'Alta')->value('prioridadid');
        $prioridadMedia = Prioridad::where('nombre', 'Media')->value('prioridadid');
        $estadoAplicadoId = EstadoLoteInsumo::where('nombre', 'Aplicado')->value('estadoloteinsumoid');
        $tiposAct = TipoActividad::pluck('tipoactividadid', 'nombre');

        $jefeAgr = $this->usuarios['jefe_agricola'];
        $agricultor = $this->usuarios['agricultor'];
        $jefePlt = $this->usuarios['jefe_planta'];
        $operarioPlt = $this->usuarios['planta'];
        $minorista = $this->usuarios['minorista'];

        // 1) Lote agrícola activo: Zanahoria - Lote 001
        $semZan = $this->insumosCampo['semilla_zanahoria'];
        $fertNpk = $this->insumosCampo['fert_npk'];
        $tInicioZan = Carbon::now()->subDays(22);

        $loteZan = Lote::create(array_merge(LoteDefaults::enrich([
            'nombre' => 'Zanahoria - Lote 001',
            'codigo_trazabilidad' => 'TRAZ-ZAN-2026-001',
            'cultivoid' => $this->cultivos['Zanahoria']->cultivoid,
            'usuarioid' => $agricultor->usuarioid,
            'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('en_crecimiento'),
            'superficie' => 2.5,
            'unidadsuperficieid' => $haId,
            'ubicacion' => 'Finca Norte — Parcela B, Santa Cruz',
            'latitud' => -17.7190,
            'longitud' => -63.1640,
            'insumosemillaid' => $semZan->insumoid,
            'cantidad_semilla_planificada' => 20.0,
        ], false), [
            'fechasiembra' => $tInicioZan->copy()->addDays(2),
            'fechacreacion' => $tInicioZan,
            'fechamodificacion' => now(),
        ]));

        HistorialEstadoLote::create([
            'loteid' => $loteZan->loteid,
            'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('sembrado'),
            'fecha_cambio' => $tInicioZan->copy()->addDays(2),
            'observaciones' => 'Siembra de Zanahoria Imperator completada.',
            'usuarioid' => $jefeAgr->usuarioid,
        ]);
        HistorialEstadoLote::create([
            'loteid' => $loteZan->loteid,
            'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('en_crecimiento'),
            'fecha_cambio' => $tInicioZan->copy()->addDays(12),
            'observaciones' => 'Brote uniforme; entra en etapa de manejo nutricional.',
            'usuarioid' => $jefeAgr->usuarioid,
        ]);

        // 2 actividades cerradas (Siembra + Riego)
        $actSiembra = Actividad::create([
            'loteid' => $loteZan->loteid,
            'usuarioid' => $jefeAgr->usuarioid,
            'usuarioid_ejecutor' => $agricultor->usuarioid,
            'tipoactividadid' => $tiposAct['Siembra'],
            'prioridadid' => $prioridadMedia,
            'descripcion' => 'Siembra de Zanahoria Imperator en surcos',
            'fechainicio' => $tInicioZan->copy()->addDays(2)->setTime(8, 0),
            'fechafin' => $tInicioZan->copy()->addDays(2)->setTime(11, 30),
            'fecha_planificada' => $tInicioZan->copy()->addDays(2)->toDateString(),
            'orden_secuencia' => 1,
            'observaciones' => 'Semilla aplicada uniformemente.',
        ]);

        $saldoAntZ = (float) $semZan->stock;
        $saldoPostZ = max(0.0, $saldoAntZ - 20.0);
        $semZan->update(['stock' => $saldoPostZ]);
        LoteInsumo::create([
            'loteid' => $loteZan->loteid,
            'insumoid' => $semZan->insumoid,
            'actividadid' => $actSiembra->actividadid,
            'usuarioid' => $agricultor->usuarioid,
            'cantidadusada' => 20.0,
            'fechauo' => $tInicioZan->copy()->addDays(2),
            'costototal' => 1100.0,
            'estadoloteinsumoid' => $estadoAplicadoId,
            'observaciones' => 'Siembra inicial Zanahoria - Lote 001',
        ]);
        $this->registrarMovimiento(
            $this->almacenes['agr_norte']->almacenid,
            $semZan->insumoid,
            $this->tiposMovimiento['consumo_interno']->tipo_movimiento_almacenid,
            $agricultor->usuarioid,
            $kgId,
            20.0,
            $saldoAntZ,
            $saldoPostZ,
            $tInicioZan->copy()->addDays(2),
            'ACT-'.$actSiembra->actividadid,
            'Consumo de semilla en Zanahoria - Lote 001'
        );

        Actividad::create([
            'loteid' => $loteZan->loteid,
            'usuarioid' => $jefeAgr->usuarioid,
            'usuarioid_ejecutor' => $agricultor->usuarioid,
            'tipoactividadid' => $tiposAct['Riego'],
            'prioridadid' => $prioridadMedia,
            'descripcion' => 'Riego inicial por aspersión',
            'fechainicio' => $tInicioZan->copy()->addDays(6)->setTime(7, 0),
            'fechafin' => $tInicioZan->copy()->addDays(6)->setTime(9, 30),
            'fecha_planificada' => $tInicioZan->copy()->addDays(6)->toDateString(),
            'orden_secuencia' => 2,
            'observaciones' => 'Humedad óptima alcanzada.',
        ]);

        // 2 actividades PENDIENTES para demostrar cierre en vivo desde Mobile/Web
        Actividad::create([
            'loteid' => $loteZan->loteid,
            'usuarioid' => $jefeAgr->usuarioid,
            'usuarioid_ejecutor' => $agricultor->usuarioid,
            'tipoactividadid' => $tiposAct['Fertilización'],
            'prioridadid' => $prioridadAlta,
            'descripcion' => 'Fertilización NPK de crecimiento (25 kg planificados)',
            'fechainicio' => now()->setTime(8, 0),
            'fechafin' => null,
            'fecha_planificada' => now()->toDateString(),
            'orden_secuencia' => 3,
            'observaciones' => 'Aplicar en toda la parcela en horario matutino.',
            'detalle_json' => json_encode([
                'insumos_planificados' => [
                    [
                        'insumoid' => $fertNpk->insumoid,
                        'almacenid' => $this->almacenes['agr_norte']->almacenid,
                        'nombre' => $fertNpk->nombre,
                        'cantidad' => 25,
                        'unidad' => 'kg',
                    ],
                ],
            ], JSON_UNESCAPED_UNICODE),
        ]);

        Actividad::create([
            'loteid' => $loteZan->loteid,
            'usuarioid' => $jefeAgr->usuarioid,
            'usuarioid_ejecutor' => $agricultor->usuarioid,
            'tipoactividadid' => $tiposAct['Control de plagas'],
            'prioridadid' => $prioridadMedia,
            'descripcion' => 'Control preventivo de plagas en follaje',
            'fechainicio' => now()->addDay()->setTime(8, 0),
            'fechafin' => null,
            'fecha_planificada' => now()->addDay()->toDateString(),
            'orden_secuencia' => 4,
            'observaciones' => 'Seleccionar bioinsecticida o fungicida según evaluación en campo.',
        ]);

        // 2) Envío agrícola pendiente de asignación (listo para aceptar/asignar transporte en vivo)
        $pedidoPend = Pedido::create([
            'numero_solicitud' => 'PED-20261122-0001',
            'nombre_planta' => $this->almacenes['planta']->nombre,
            'origen_latitud' => -17.7165,
            'origen_longitud' => -63.1662,
            'origen_direccion' => $this->almacenes['agr_norte']->nombre.' · '.$this->almacenes['agr_norte']->ubicacion,
            'latitud' => -17.7689,
            'longitud' => -63.1415,
            'direccion_texto' => $this->almacenes['planta']->ubicacion,
            'estado' => PedidoCatalogo::ESTADO_INICIAL,
            'fechapedido' => now()->subHours(4),
            'fechaEntregaDeseada' => now()->addDay()->toDateString(),
            'hora_recogida' => '08:30',
            'hora_entrega_estimada' => '11:00',
            'creado_por_usuarioid' => $jefeAgr->usuarioid,
            'observaciones' => 'Envío demo pendiente de asignación de transportista y vehículo.',
        ]);

        DetallePedido::create([
            'pedidoid' => $pedidoPend->pedidoid,
            'produccionalmacenamientoid' => $cadenaTomate['pa']->produccionalmacenamientoid,
            'producto_ref' => 'cosecha:'.$cadenaTomate['pa']->produccionalmacenamientoid,
            'cultivo_personalizado' => 'Tomate fresco (Tomate - Lote 001)',
            'cantidad' => 500.0,
            'observaciones' => 'Segundo despacho de cosecha de tomate disponible.',
        ]);

        // 3) Lote de planta en ejecución con tarea pendiente para planta@agrofusion.com
        $plantillaSalsa = PlantillaTransformacion::with(['pasos.proceso', 'pasos.maquina'])
            ->where('nombre', 'Salsa de tomate')
            ->first();
        if ($plantillaSalsa) {
            $lotePlantaActivo = LoteProduccionPedido::create([
                'pedidoid' => $cadenaTomate['pedido_agr']->pedidoid,
                'codigo_lote' => 'LPP-20261122-002',
                'nombre' => 'Salsa de Tomate Artesanal · Lote 2',
                'producto' => 'Salsa de Tomate Artesanal',
                'plantillatransformacionid' => $plantillaSalsa->plantillatransformacionid,
                'procesoplantaid' => $plantillaSalsa->pasos->first()?->procesoplantaid,
                'fecha_creacion' => now()->toDateString(),
                'hora_inicio' => now()->subHours(3),
                'cantidad_objetivo' => 255.0,
                'cantidad_producida' => 0,
                'unidadmedidaid' => $kgId,
                'empaque_catalogo_slug' => 'frasco',
                'empaque_nombre_personalizado' => 'Frasco 340 g',
                'empaque_peso_neto_kg' => 0.34,
                'empaque_tipo_envase' => 'frasco',
                'modo_planificacion' => EmpaquePlantaCatalogo::MODO_EMPAQUES,
                'cantidad_empaques_objetivo' => 750,
                'observaciones' => 'Lote en curso para demostración de ejecución de etapas de planta.',
            ]);

            LoteProduccionMateriaPrima::create([
                'loteproduccionpedidoid' => $lotePlantaActivo->loteproduccionpedidoid,
                'materiaprimaloteid' => $cadenaTomate['mp_lote']->materiaprimaloteid,
                'insumoid' => $cadenaTomate['ins_mp_planta']->insumoid,
                'cantidad_planificada' => 300.0,
                'cantidad_usada' => 300.0,
            ]);

            foreach ($plantillaSalsa->pasos->sortBy('orden') as $idx => $paso) {
                $rutaPasoId = DB::table('lote_produccion_ruta_paso')->insertGetId([
                    'loteproduccionpedidoid' => $lotePlantaActivo->loteproduccionpedidoid,
                    'orden' => $paso->orden,
                    'procesoplantaid' => $paso->procesoplantaid,
                    'maquinaplantaid' => $paso->maquinaplantaid,
                    'notas' => $paso->notas,
                    'plantillapasoid' => $paso->plantillapasoid,
                    'created_at' => now()->subHours(3),
                    'updated_at' => now()->subHours(3),
                ]);

                $completado = $idx < 2;
                $regId = null;
                if ($completado) {
                    $pm = ProcesoMaquinaPlanta::firstOrCreate(
                        ['procesoplantaid' => $paso->procesoplantaid, 'maquinaplantaid' => $paso->maquinaplantaid],
                        ['orden_paso' => $paso->orden, 'nombre' => $paso->proceso?->nombre ?? 'Etapa', 'tiempo_estimado' => 60]
                    );
                    $reg = RegistroProcesoMaquinaPlanta::create([
                        'procesomaquinaplantaid' => $pm->procesomaquinaplantaid,
                        'loteid' => $cadenaTomate['lote']->loteid,
                        'loteproduccionpedidoid' => $lotePlantaActivo->loteproduccionpedidoid,
                        'usuarioid' => $operarioPlt->usuarioid,
                        'variables_ingresadas' => json_encode(['estado' => 'ok']),
                        'cumple_estandar' => true,
                        'observaciones' => 'Paso completado en turno matutino.',
                        'hora_inicio' => now()->subHours(3 - $idx),
                        'hora_fin' => now()->subHours(2 - $idx),
                        'fecha_registro' => now()->subHours(2 - $idx),
                    ]);
                    $regId = $reg->registroprocesomaquinaplantaid;
                }

                DB::table('asignacion_etapa_planta')->insert([
                    'loteproduccionpedidoid' => $lotePlantaActivo->loteproduccionpedidoid,
                    'procesoplantaid' => $paso->procesoplantaid,
                    'maquinaplantaid' => $paso->maquinaplantaid,
                    'operador_usuarioid' => $operarioPlt->usuarioid,
                    'asignado_por_usuarioid' => $jefePlt->usuarioid,
                    'estado' => $completado ? 'completada' : 'pendiente',
                    'observaciones' => $completado ? 'Etapa completada.' : 'Listo para registrar variables en planta.',
                    'registroprocesomaquinaplantaid' => $regId,
                    'creado_en' => now()->subHours(3),
                    'completada_en' => $completado ? now()->subHours(2 - $idx) : null,
                    'loteproduccionrutapasoid' => $rutaPasoId,
                    'orden' => $paso->orden,
                ]);
            }
        }

        // 4) Pedido minorista pendiente (Supermercado Norte solicita 100 frascos al Mayorista)
        $pedidoPdvPend = PedidoDistribucion::create([
            'numero_solicitud' => 'PDV-20261122-0001',
            'puntoventaid' => $this->puntosVenta['norte']->puntoventaid,
            'almacen_planta_origenid' => $this->almacenes['planta']->almacenid,
            'almacen_mayorista_origenid' => $this->almacenes['mayorista']->almacenid,
            'estado' => PedidoDistribucionCatalogo::ESTADO_PENDIENTE,
            'tipo_solicitud' => PedidoDistribucionCatalogo::TIPO_SOLICITUD_STOCK,
            'canal_origen' => PedidoDistribucionCatalogo::CANAL_SISTEMA,
            'fechapedido' => now()->subHours(2),
            'fecha_entrega_deseada' => now()->addDay()->toDateString(),
            'hora_entrega_deseada' => '15:00',
            'creado_por_usuarioid' => $minorista->usuarioid,
            'observaciones' => 'Reposición semanal para Supermercado Norte (pendiente de aprobación mayorista).',
        ]);

        DetallePedidoDistribucion::create([
            'pedidodistribucionid' => $pedidoPdvPend->pedidodistribucionid,
            'insumoid' => $cadenaTomate['ins_prod_may']->insumoid,
            'insumo_planta_referenciaid' => $cadenaTomate['ins_prod_planta']->insumoid,
            'insumo_presentacionid' => $cadenaTomate['pres_may']->insumo_presentacionid,
            'almacen_mayorista_origenid' => $this->almacenes['mayorista']->almacenid,
            'inventario_presentacion_loteid' => $cadenaTomate['inv_pres_may']->inventario_presentacion_loteid,
            'referencia_lote' => 'LPP-20261108-001',
            'producto_nombre' => 'Salsa de Tomate Artesanal · Frasco 340 g',
            'tipo_envase' => 'frasco',
            'cantidad' => 100,
            'observaciones' => 'Solicitud pendiente de aprobación y despacho.',
        ]);
    }

    /**
     * @param  array<string, mixed>  $extra
     */
    private function registrarMovimiento(
        int $almacenId,
        int $insumoId,
        int $tipoMovId,
        int $usuarioId,
        int $unidadMedidaId,
        float $cantidad,
        float $saldoAnterior,
        float $saldoPosterior,
        Carbon $fecha,
        string $referencia,
        string $observaciones,
        array $extra = []
    ): AlmacenMovimiento {
        return AlmacenMovimiento::create(array_merge([
            'almacenid' => $almacenId,
            'insumoid' => $insumoId,
            'tipo_movimiento_almacenid' => $tipoMovId,
            'usuarioid' => $usuarioId,
            'unidadmedidaid' => $unidadMedidaId,
            'fecha' => $fecha->toDateString(),
            'cantidad' => $cantidad,
            'saldo_anterior' => $saldoAnterior,
            'saldo_posterior' => $saldoPosterior,
            'referencia' => $referencia,
            'observaciones' => $observaciones,
        ], $extra));
    }

    private function imprimirResumen(): void
    {
        if (! $this->command) {
            return;
        }

        $service = app(TrazabilidadProductoPdvService::class);
        $this->command->newLine();
        $this->command->info('══════════════════════════════════════════════════════════════');
        $this->command->info('  AgroFusion Demo Seeder — Base limpia y trazabilidad lista');
        $this->command->info('══════════════════════════════════════════════════════════════');
        $this->command->info('  Contraseña de todas las cuentas: '.self::DEMO_PASSWORD);
        $this->command->info('  Admin:           admin@agrofusion.com');
        $this->command->info('  Jefe Agrícola:   jefe.agricola@agrofusion.com');
        $this->command->info('  Agricultor:      agricultor@agrofusion.com / agricultor2@agrofusion.com');
        $this->command->info('  Jefe Planta:     jefe.planta@agrofusion.com');
        $this->command->info('  Planta:          planta@agrofusion.com');
        $this->command->info('  Jefe Mayorista:  jefe.mayorista@agrofusion.com');
        $this->command->info('  Mayorista:       mayorista@agrofusion.com');
        $this->command->info('  Minorista:       minorista@agrofusion.com');
        $this->command->info('  Transportistas:  chofer.agricola / chofer.agricola2 / chofer.planta / chofer.mayorista @agrofusion.com');
        foreach (['TRZ-PDV-TOMATE-202601', 'TRZ-PDV-PAPA-202601'] as $qr) {
            $ins = Insumo::where('codigo_trazabilidad', $qr)->first();
            if ($ins) {
                $this->command->info('  QR '.$qr.': '.$service->urlPublica($ins));
            }
        }
        $this->command->info('══════════════════════════════════════════════════════════════');
    }
}
