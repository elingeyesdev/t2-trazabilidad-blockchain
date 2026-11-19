<?php

namespace Database\Seeders;

use App\Models\{Actividad, Almacen, Cultivo, Insumo, Lote, Prioridad, TipoActividad, TipoAlmacen, TipoInsumo, UnidadMedida, Usuario};
use App\Services\ActividadCierreService;
use App\Support\{CuentaEstado, LoteDefaults};
use Illuminate\Database\Seeder;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;

/** Additive local demo. Re-running never resets an existing account, task or stock. */
class DemoFlujoActividadesSeeder extends Seeder
{
    public function run(): void
    {
        if (config('database.default') !== 'sqlite') {
            throw new \RuntimeException('Esta demostración está limitada a la base SQLite local.');
        }
        $jefe = $this->usuario('jefe.agricultor', 'Jefe', 'jefe_agricultor');
        $ana = $this->usuario('operario.ana', 'Ana', 'agricultor', $jefe);
        $luis = $this->usuario('operario.luis', 'Luis', 'agricultor', $jefe);
        $jefeAjeno = $this->usuario('jefe.otroequipo', 'Jefe otro equipo', 'jefe_agricultor');
        $ajeno = $this->usuario('operario.otroequipo', 'Operario otro equipo', 'agricultor', $jefeAjeno);
        $kg = UnidadMedida::firstOrCreate(['nombre' => 'Kilogramo'], ['abreviatura' => 'kg', 'categoria' => 'peso']);
        $litro = UnidadMedida::firstOrCreate(['nombre' => 'Litro'], ['abreviatura' => 'L', 'categoria' => 'volumen']);
        $almacen = Almacen::where('responsable_usuarioid', $jefe->usuarioid)->where('ambito', 'agricola')->where('activo', true)->get();
        if ($almacen->count() > 1) {
            throw new \RuntimeException('El jefe tiene más de un almacén agrícola activo; no se eligió uno arbitrariamente.');
        }
        $almacen = $almacen->first() ?? Almacen::create([
            'nombre' => 'DEMO EDT - Almacén agrícola', 'ubicacion' => 'Parcela demostrativa La Paz',
            'capacidad' => 10000, 'unidadmedidaid' => $kg->unidadmedidaid,
            'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Agrícola'])->tipoalmacenid,
            'ambito' => 'agricola', 'activo' => true, 'responsable_usuarioid' => $jefe->usuarioid,
        ]);
        $semilla = $this->insumo('DEMO EDT - Semilla de papa', 'Material de Siembra', $kg, $almacen, '500.000000');
        $fertilizante = $this->insumo('DEMO EDT - Fertilizante', 'Fertilizantes', $kg, $almacen, '100.000000');
        $plagas = $this->insumo('DEMO EDT - Control de plagas', 'Control de plagas', $litro, $almacen, '20.000000');
        $crecimiento = $this->lote('DEMO EDT - 01 Crecimiento', $jefe, $semilla);
        $preparacion = $this->lote('DEMO EDT - 02 Preparación', $jefe, $semilla);
        $legado = $this->lote('DEMO EDT - 03 Sin evidencia', $jefe, $semilla);
        $otro = $this->lote('DEMO EDT - 04 Otro equipo', $jefeAjeno, null);

        $this->cerrar($this->actividad($crecimiento, $ana, 'Preparación del terreno', 1, -5), $ana, [], 'Suelo preparado y nivelado.');
        $this->cerrar($this->actividad($crecimiento, $ana, 'Siembra', 2, -4, $semilla, '25.000'), $ana, [$this->consumo($semilla, '25.000')], 'Siembra demostrativa terminada en los surcos previstos.');
        $this->cerrar($this->actividad($crecimiento, $ana, 'Fertilización', 3, -2, $fertilizante, '2.500'), $ana, [$this->consumo($fertilizante, '2.500')], 'Aplicación uniforme: consumo real de 2.500 kg.');
        $riego = $this->actividad($crecimiento, $luis, 'Riego', 4, -1);
        $this->cerrar($riego, $luis, [], 'Riego por goteo completado, sin consumo de insumos de almacén.');
        $this->actividad($crecimiento, $ana, 'Fertilización', 5, 0, $fertilizante, '3.250');
        $this->actividad($crecimiento, $luis, 'Control de plagas', 6, 1, $plagas, '0.750');
        $this->actividad($crecimiento, $ana, 'Riego', 7, 3);
        $this->actividad($preparacion, $luis, 'Preparación del terreno', 1, 0);
        $this->actividad($preparacion, $luis, 'Siembra', 2, 1, $semilla, '20.000');
        // Explicit historical fixture: completed before photos/results were required.
        $historica = $this->actividad($legado, $luis, 'Preparación del terreno', 1, -3);
        if ($historica->wasRecentlyCreated) {
            $historica->update(['fechafin' => now()->subDays(3), 'usuarioid_ejecutor' => $luis->usuarioid,
                'observaciones' => 'DEMO: registro histórico sin fotografía ni consumo; no representa un cierre nuevo.']);
        }
        $this->actividad($legado, $luis, 'Siembra', 2, 0, $semilla, '15.000');
        $this->actividad($otro, $ajeno, 'Preparación del terreno', 1, 0);
        $foto = $crecimiento->actividades()->whereNotNull('evidencia_foto_path')->value('evidencia_foto_path');
        if ($foto && ! Storage::disk('local')->exists('demo-flujo/foto-prueba-cierre.png')) {
            Storage::disk('local')->copy($foto, 'demo-flujo/foto-prueba-cierre.png');
        }
        $this->command?->info('DEMO EDT preparada. Contraseña inicial de cuentas nuevas: 12345678. No se restablecieron cuentas ni existencias existentes.');
    }

    private function usuario(string $identificador, string $nombre, string $rol, ?Usuario $jefe = null): Usuario
    {
        $usuario = Usuario::firstOrCreate(['email' => $identificador.'@agrofusion.local'], [
            'nombre' => $nombre, 'apellido' => 'Demo', 'nombreusuario' => str_replace('.', '_', $identificador),
            'passwordhash' => Hash::make('12345678'), 'role' => $rol, 'activo' => true,
            'estado_cuenta' => CuentaEstado::APROBADO, 'supervisor_usuarioid' => $jefe?->usuarioid,
            'fecharegistro' => now(), 'fechamodificacion' => now(),
        ]);
        if ($usuario->wasRecentlyCreated) {
            $usuario->assignRole($rol);
        }
        if (! $usuario->hasRole($rol) || ($jefe && (int) $usuario->supervisor_usuarioid !== (int) $jefe->usuarioid)) {
            throw new \RuntimeException('La cuenta demo existente tiene un rol o equipo incompatible: '.$usuario->email);
        }
        return $usuario;
    }

    private function insumo(string $nombre, string $tipo, UnidadMedida $unidad, Almacen $almacen, string $stock): Insumo
    {
        return Insumo::firstOrCreate(['nombre' => $nombre, 'almacenid' => $almacen->almacenid], [
            'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => $tipo])->tipoinsumoid,
            'unidadmedidaid' => $unidad->unidadmedidaid, 'stock' => $stock, 'stockminimo' => 1,
            'preciounitario' => 1, 'proveedor' => 'Demostración local', 'descripcion' => 'Datos DEMO EDT para verificar actividades.',
        ]);
    }

    private function lote(string $nombre, Usuario $jefe, ?Insumo $semilla): Lote
    {
        $lote = Lote::firstOrCreate(['nombre' => $nombre, 'usuarioid' => $jefe->usuarioid], LoteDefaults::enrich([
            'superficie' => 1, 'cultivoid' => Cultivo::firstOrCreate(['nombre' => 'Papa'])->cultivoid,
            'ubicacion' => 'Parcela demostrativa - La Paz', 'latitud' => -16.5, 'longitud' => -68.15,
            'insumosemillaid' => $semilla?->insumoid, 'cantidad_semilla_planificada' => $semilla ? '20.000' : null,
        ]));
        if ($lote->wasRecentlyCreated) {
            LoteDefaults::registrarHistorialInicial($lote);
        }
        return $lote;
    }

    private function consumo(Insumo $insumo, string $cantidad): array
    {
        return ['insumoid' => $insumo->insumoid, 'almacenid' => $insumo->almacenid, 'cantidad' => $cantidad];
    }

    private function actividad(Lote $lote, Usuario $operario, string $tipo, int $orden, int $dias, ?Insumo $insumo = null, string $cantidad = '0'): Actividad
    {
        $detalle = $insumo ? ['modo' => 'insumos', 'stock_aplicado' => false, 'insumos' => [array_merge($this->consumo($insumo, $cantidad), [
            'nombre' => $insumo->nombre, 'unidadmedidaid' => $insumo->unidadmedidaid,
            'unidad' => $insumo->unidadMedida?->abreviatura ?? $insumo->unidadMedida?->nombre,
        ])]] : (str_contains($tipo, 'Riego') ? ['modo' => 'riego', 'riego' => ['key' => 'goteo', 'label' => 'Riego por goteo']] : []);
        return Actividad::firstOrCreate(['loteid' => $lote->loteid, 'descripcion' => 'DEMO EDT '.$orden.' - '.$tipo], [
            'usuarioid' => $operario->usuarioid, 'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => $tipo])->tipoactividadid,
            'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->prioridadid,
            'fecha_planificada' => now()->addDays($dias)->toDateString(), 'fechainicio' => now()->addDays($dias)->setTime(8, 0),
            'orden_secuencia' => $orden, 'observaciones' => 'Datos de demostración para validación del flujo EDT.',
            'detalle_json' => json_encode($detalle, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        ]);
    }

    private function cerrar(Actividad $actividad, Usuario $operario, array $consumos, string $resultado): void
    {
        if ($actividad->fechafin !== null) {
            return;
        }
        // Deliberately labelled test image; never presented as a real field photograph.
        $archivo = tempnam(sys_get_temp_dir(), 'edt-demo-');
        try {
            $imagen = imagecreatetruecolor(800, 450);
            imagefill($imagen, 0, 0, imagecolorallocate($imagen, 237, 245, 240));
            $color = imagecolorallocate($imagen, 25, 92, 57);
            imagestring($imagen, 5, 35, 60, 'DEMO EDT - IMAGEN DE PRUEBA', $color);
            imagestring($imagen, 5, 35, 130, 'Actividad #'.$actividad->actividadid.' - Lote #'.$actividad->loteid, $color);
            imagestring($imagen, 4, 35, 200, 'Evidencia sintetica para verificar el sistema.', $color);
            imagepng($imagen, $archivo);
            imagedestroy($imagen);
            $request = Request::create('/', 'POST', ['resultado' => $resultado, 'consumos' => $consumos], [], [
                'evidencia_foto' => new UploadedFile($archivo, 'demo-'.$actividad->actividadid.'.png', 'image/png', null, true),
            ]);
            $request->setUserResolver(fn () => $operario);
            app(ActividadCierreService::class)->cerrar($request, $actividad);
        } finally {
            if (is_file($archivo)) {
                unlink($archivo);
            }
        }
    }
}
