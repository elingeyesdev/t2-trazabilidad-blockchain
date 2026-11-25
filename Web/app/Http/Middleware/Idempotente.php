<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Contracts\Cache\LockTimeoutException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * Evita registros duplicados cuando un cliente móvil reintenta un POST cuya
 * respuesta se perdió. Si llega el mismo `Idempotency-Key` del mismo usuario
 * en la misma ruta, devuelve la respuesta ya guardada sin volver a ejecutar.
 */
class Idempotente
{
    private const VIGENCIA_HORAS = 24;

    public function handle(Request $request, Closure $next): Response
    {
        $clave = $request->header('Idempotency-Key');
        $usuario = $request->user()?->getAuthIdentifier();

        if (! $request->isMethod('POST') || ! is_string($clave) || $clave === '' || strlen($clave) > 100 || $usuario === null) {
            return $next($request);
        }

        $huella = 'idempotente:'.sha1($usuario.'|'.$request->path().'|'.$clave);

        try {
            return Cache::lock($huella.':lock', 30)->block(10, function () use ($request, $next, $huella) {
                if ($guardada = Cache::get($huella)) {
                    return $this->repetir($guardada);
                }

                $respuesta = $next($request);

                if ($respuesta->isSuccessful()) {
                    Cache::put($huella, [
                        'estado' => $respuesta->getStatusCode(),
                        'contenido' => $respuesta->getContent(),
                        'tipo' => $respuesta->headers->get('Content-Type', 'application/json'),
                    ], now()->addHours(self::VIGENCIA_HORAS));
                }

                return $respuesta;
            });
        } catch (LockTimeoutException) {
            return response()->json(['message' => 'La solicitud anterior sigue en proceso. Intenta de nuevo en unos segundos.'], 409);
        }
    }

    private function repetir(array $guardada): Response
    {
        return response($guardada['contenido'], $guardada['estado'], [
            'Content-Type' => $guardada['tipo'],
            'Idempotent-Replayed' => 'true',
        ]);
    }
}
