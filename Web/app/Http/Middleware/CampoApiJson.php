<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** Keep field and authentication errors JSON even when a mobile client omits Accept. */
class CampoApiJson
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->is('api/lotes', 'api/lotes/*', 'api/actividades', 'api/actividades/*', 'api/producciones', 'api/producciones/*', 'api/almacenes/*', 'api/almacen-movimientos*', 'api/insumos*', 'api/planta/*', 'api/pedidos*', 'api/certificaciones*')) {
            $request->headers->set('Accept', 'application/json');
        }

        return $next($request);
    }
}
