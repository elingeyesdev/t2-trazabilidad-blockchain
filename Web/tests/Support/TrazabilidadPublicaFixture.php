<?php

namespace Tests\Support;

use App\Models\Cultivo;
use App\Models\EstadoLoteTipo;
use App\Models\Insumo;
use App\Models\Lote;
use App\Models\TipoInsumo;
use App\Models\UnidadMedida;
use App\Models\Usuario;

/** Registros aislados: nunca consulta ni prepara la base operativa local. */
class TrazabilidadPublicaFixture
{
    public static function crear(): array
    {
        $usuario = Usuario::create([
            'nombre' => 'IDENTIDAD-PRIVADA-61', 'apellido' => 'No publicar',
            'nombreusuario' => 'privado61', 'email' => 'privado61@example.test',
            'telefono' => 'TEL-PRIVADO-61', 'passwordhash' => 'HASH-PRIVADO-61',
            'informacionadicional' => 'NOTA-USUARIO-PRIVADA-61',
            'activo' => true, 'estado_cuenta' => 'aprobado',
        ]);
        $kg = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
        $ha = UnidadMedida::firstOrCreate(['abreviatura' => 'ha'], ['nombre' => 'Hectarea', 'categoria' => 'superficie']);
        $cultivo = Cultivo::create(['nombre' => 'Zanahoria']);
        $estado = EstadoLoteTipo::firstOrCreate(['nombre' => 'Planificado']);
        $lote = Lote::create([
            'usuarioid' => $usuario->getKey(), 'cultivoid' => $cultivo->getKey(),
            'nombre' => 'Origen de zanahoria', 'codigo_trazabilidad' => 'TRAZ-20261124-ABC123',
            'ubicacion' => 'DOMICILIO-PRIVADO-61', 'superficie' => 1, 'unidadsuperficieid' => $ha->getKey(),
            'estadolotetipoid' => $estado->getKey(),
            'latitud' => -17.123456, 'longitud' => -63.987654,
            'imagenurl' => 'private/fotos/FOTO-PRIVADA-61.jpg',
        ]);
        $pdv = Insumo::create([
            'nombre' => 'Zanahoria envasada', 'codigo_trazabilidad' => 'TRZ-PDV-20261124-DEF456',
            'tipoinsumoid' => TipoInsumo::create(['nombre' => 'Producto terminado'])->getKey(),
            'unidadmedidaid' => $kg->getKey(), 'stock' => 12,
            'proveedor' => 'PROVEEDOR-PRIVADO-61', 'descripcion' => 'NOTA-INTERNA-61',
            'imagenurl' => 'private/productos/FOTO-PDV-PRIVADA-61.jpg',
        ]);

        return compact('usuario', 'kg', 'ha', 'cultivo', 'lote', 'pdv');
    }
}
