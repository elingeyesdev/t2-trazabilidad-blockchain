<?php

namespace App\Services;

use App\Models\Usuario;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/** Reintentos explícitos por usuario, siguiendo solicitud_id/huella de las emisiones existentes. */
class PedidoSolicitudService
{
    public function ejecutar(Request $request, string $modelo, callable $crear)
    {
        $request->validate(['solicitud_id' => ['sometimes', 'uuid']]);
        $entrada = $request->except(['_token', '_method', 'solicitud_id']);
        $ordenar = function (array $datos) use (&$ordenar): array {
            ksort($datos);
            foreach ($datos as &$valor) {
                if (is_array($valor)) {
                    $valor = $ordenar($valor);
                }
            }

            return $datos;
        };
        $huella = hash('sha256', json_encode($ordenar($entrada), JSON_THROW_ON_ERROR));

        $operacion = function () use ($request, $modelo, $crear, $huella) {
            // Mutex compartido entre conexiones, también para solicitudes sin identificador.
            $uid = $request->user()->getKey();
            if (DB::getDriverName() === 'sqlite') {
                DB::table('usuario')->where('usuarioid', $uid)->update(['activo' => DB::raw('activo')]);
            }
            Usuario::whereKey($uid)->lockForUpdate()->firstOrFail();
            $id = $request->input('solicitud_id');
            if ($id) {
                $anterior = $modelo::where('creado_por_usuarioid', $uid)->where('solicitud_id', $id)->first();
                if ($anterior) {
                    abort_unless(hash_equals((string) $anterior->solicitud_huella, $huella), 409, 'La solicitud identificada como reintento tiene datos diferentes.');

                    \App\Support\PedidoMovilAcceso::asegurar($request->user(), $anterior);

                    return $anterior;
                }
            }
            $pedido = $crear();
            $pedido->forceFill(['solicitud_id' => $id, 'solicitud_huella' => $id ? $huella : null])->save();

            return $pedido;
        };
        for ($intento = 0; ; $intento++) {
            try {
                return DB::transaction($operacion, 5);
            } catch (\Illuminate\Database\QueryException $e) {
                // La numeración correlativa existente puede competir entre productos distintos.
                if ($intento >= 2 || ! in_array((string) $e->getCode(), ['23505', '23000'], true) || ! str_contains($e->getMessage(), 'numero_solicitud')) {
                    throw $e;
                }
            }
        }
    }
}
