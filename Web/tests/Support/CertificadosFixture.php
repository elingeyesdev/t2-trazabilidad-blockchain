<?php

namespace Tests\Support;

use App\Models\Actividad;
use App\Models\Almacen;
use App\Models\AsignacionEtapaPlanta;
use App\Models\Cultivo;
use App\Models\DestinoProduccion;
use App\Models\DetallePedido;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Lote;
use App\Models\LoteProduccionRutaPaso;
use App\Models\LoteProduccionRutaPasoVariable;
use App\Models\MaquinaPlanta;
use App\Models\Pedido;
use App\Models\Prioridad;
use App\Models\ProcesoPlanta;
use App\Models\Produccion;
use App\Models\ProduccionAlmacenamiento;
use App\Models\TipoActividad;
use App\Models\TipoAlmacen;
use App\Models\TipoMovimientoAlmacen;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Models\VariableEstandar;
use App\Services\LoteProduccionPlantaService;
use App\Services\RecepcionPlantaEnvioService;
use App\Support\AsignacionEtapaPlantaService;
use App\Support\EstadoLoteCatalogo;
use App\Support\LoteDefaults;

class CertificadosFixture
{
    public static function crear(): array
    {
        $agricola = self::usuario('jefe_agricultor', 'campo44');
        $planta = self::usuario('jefe_planta', 'planta44');
        $operario = self::usuario('planta', 'operario44');
        $operario->update(['supervisor_usuarioid' => $planta->getKey()]);
        $kg = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
        $almacen = Almacen::create(['nombre' => 'Planta antecedentes', 'ubicacion' => 'Prueba', 'ambito' => 'planta', 'activo' => true,
            'responsable_usuarioid' => $planta->getKey(), 'unidadmedidaid' => $kg->getKey(), 'capacidad' => 1000,
            'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Planta'])->getKey()]);
        TipoMovimientoAlmacen::firstOrCreate(['nombre' => 'Producción recibida', 'naturaleza' => 'ingreso'], ['activo' => true]);
        TipoMovimientoAlmacen::firstOrCreate(['nombre' => 'Consumo interno', 'naturaleza' => 'salida'], ['activo' => true]);
        $campos = [];
        $cosechas = [];
        foreach (['Tomate origen A', 'Tomate origen B'] as $nombre) {
            $l = Lote::create(['usuarioid' => $agricola->getKey(), 'nombre' => $nombre, 'ubicacion' => 'Campo de prueba', 'superficie' => 1,
                'unidadsuperficieid' => LoteDefaults::unidadHectareaId(), 'cultivoid' => Cultivo::firstOrCreate(['nombre' => 'Tomate'])->getKey(),
                'fechasiembra' => now()->subDays(30), 'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('cosechado')]);
            foreach (['Siembra', 'Riego', 'Control de plagas', 'Fertilización', 'Cosecha'] as $i => $tipo) {
                Actividad::create(['loteid' => $l->getKey(), 'usuarioid' => $agricola->getKey(), 'usuarioid_ejecutor' => $agricola->getKey(),
                    'descripcion' => $tipo.' registrada', 'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => $tipo])->getKey(),
                    'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->getKey(), 'fechainicio' => now()->subDays(2),
                    'fechafin' => now()->subDay(), 'orden_secuencia' => $i + 1, 'detalle_json' => json_encode(['cierre' => ['resultado' => $tipo.' completada']])]);
            }
            $p = Produccion::create(['loteid' => $l->getKey(), 'cantidad' => '100.123456', 'cantidad_base' => '100.123456',
                'unidadmedidaid' => $kg->getKey(), 'fechacosecha' => now()->subDay(),
                'destinoproduccionid' => DestinoProduccion::firstOrCreate(['nombre' => 'Almacenamiento'])->getKey()]);
            $cosechas[] = ProduccionAlmacenamiento::create(['produccionid' => $p->getKey(), 'almacenid' => $almacen->getKey(),
                'cantidad' => 0, 'unidadmedidaid' => $kg->getKey(), 'fechaentrada' => now()->subDay(), 'fechasalida' => now()]);
            $campos[] = $l;
        }
        $campoCertificable = $campos[0]->replicate();
        $campoCertificable->nombre = 'Campo pendiente de certificación';
        $campoCertificable->save();
        foreach ($campos[0]->actividades as $actividad) {
            $copia = $actividad->replicate();
            $copia->loteid = $campoCertificable->getKey();
            $copia->save();
        }
        $copia = $campos[0]->producciones()->first()->replicate();
        $copia->loteid = $campoCertificable->getKey();
        $copia->save();
        $pedido = Pedido::create(['numero_solicitud' => 'PED-EDT44', 'nombre_planta' => $almacen->nombre,
            'direccion_texto' => $almacen->nombre.' · GPS', 'estado' => 'en_transito', 'latitud' => -17.7, 'longitud' => -63.1]);
        $pesajes = [];
        foreach ($cosechas as $i => $cosecha) {
            $d = DetallePedido::create(['pedidoid' => $pedido->getKey(), 'produccionalmacenamientoid' => $cosecha->getKey(),
                'producto_ref' => 'cosecha:'.$cosecha->getKey(), 'cultivo_personalizado' => $campos[$i]->nombre, 'cantidad' => '100.123456']);
            $pesajes[$d->getKey()] = '100.123456';
        }
        $envio = EnvioAsignacionMultiple::create(['pedidoid' => $pedido->getKey(), 'externo_envio_id' => 'ENV-EDT44', 'estado' => 'en_transporte_planta']);
        app(RecepcionPlantaEnvioService::class)->confirmarDesdePedido($pedido, $planta, $pesajes);
        $recibidas = $envio->fresh()->recepcion_planta_datos['lineas'];
        $lineas = array_map(fn ($r) => ['insumoid' => $r['insumoid'], 'cantidad' => '5.123', 'materiaprimaloteid' => $r['materiaprimaloteid']], $recibidas);
        $lote = app(LoteProduccionPlantaService::class)->crear($planta, 'Tomate', $pedido->getKey(), 10.246, $kg->getKey(), $lineas);
        $proceso = ProcesoPlanta::firstOrCreate(['nombre' => 'Empaquetado'], ['activo' => true]);
        $maquina = MaquinaPlanta::firstOrCreate(['codigo' => 'SE-10'], ['nombre' => 'Selladora', 'activo' => true]);
        $paso = LoteProduccionRutaPaso::create(['loteproduccionpedidoid' => $lote->getKey(), 'orden' => 1,
            'procesoplantaid' => $proceso->getKey(), 'maquinaplantaid' => $maquina->getKey()]);
        $variable = VariableEstandar::create(['codigo' => 'PESO-44', 'nombre' => 'Cantidad procesada', 'unidad' => 'kg', 'activo' => true]);
        LoteProduccionRutaPasoVariable::create(['loteproduccionrutapasoid' => $paso->getKey(), 'variableestandarid' => $variable->getKey(),
            'valor_minimo' => 1, 'valor_maximo' => 100, 'obligatorio' => true]);
        $asignacion = AsignacionEtapaPlanta::create(['loteproduccionpedidoid' => $lote->getKey(), 'loteproduccionrutapasoid' => $paso->getKey(),
            'procesoplantaid' => $proceso->getKey(), 'maquinaplantaid' => $maquina->getKey(), 'operador_usuarioid' => $operario->getKey(),
            'asignado_por_usuarioid' => $planta->getKey(), 'orden' => 1, 'estado' => 'pendiente', 'creado_en' => now()->subHour()]);
        $registro = app(AsignacionEtapaPlantaService::class)->completar($asignacion, ['parametros' => [
            ['variableestandarid' => $variable->getKey(), 'valor' => '10.123456']]], $operario);

        return compact('campoCertificable', 'agricola', 'planta', 'operario', 'almacen', 'kg', 'campos', 'cosechas', 'pedido', 'envio', 'lote', 'asignacion', 'registro', 'recibidas');
    }

    public static function usuario(string $rol, string $nombre): Usuario
    {
        $u = Usuario::create(['nombre' => $nombre, 'apellido' => 'Antecedentes', 'nombreusuario' => $nombre,
            'email' => $nombre.'@edt44.test', 'passwordhash' => bcrypt('prueba123'), 'role' => $rol,
            'activo' => true, 'estado_cuenta' => 'aprobado', 'bienvenida_vista' => true]);
        $u->syncRoles([$rol]);

        return $u;
    }
}
