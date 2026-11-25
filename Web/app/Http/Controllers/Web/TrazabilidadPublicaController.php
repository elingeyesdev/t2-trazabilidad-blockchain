<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Services\ConsultaTrazabilidadPublicaService;
use App\Support\CodigoTrazabilidadPublica;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpException;

class TrazabilidadPublicaController extends Controller
{
    public function index(Request $request)
    {
        if (! $request->query->has('codigo')) {
            return $this->buscador();
        }
        $codigo = $request->query('codigo');
        if (! is_string($codigo)) {
            return $this->buscador('', 'Escribe un código de trazabilidad válido.', 422);
        }
        try {
            $normalizado = CodigoTrazabilidadPublica::normalizar($codigo);
        } catch (ValidationException $e) {
            return $this->buscador($codigo, $e->errors()['codigo'][0], 422);
        }

        return redirect()->route('trazabilidad.publica', ['codigo' => $normalizado]);
    }

    public function show(Request $request, string $codigo, ConsultaTrazabilidadPublicaService $consulta)
    {
        try {
            $reporte = $consulta->consultar($codigo, $request);
        } catch (ValidationException $e) {
            return $this->buscador($codigo, $e->errors()['codigo'][0], 422);
        } catch (HttpException $e) {
            if (! in_array($e->getStatusCode(), [404, 409], true)) {
                throw $e;
            }

            return $this->buscador($codigo, $e->getStatusCode() === 404
                ? 'Revisa el código del producto o intenta otra búsqueda.'
                : 'Este código no permite identificar un único registro. Consulta con el emisor.', $e->getStatusCode());
        }

        return response()->view('trazabilidad.publica', compact('reporte'))
            ->header('Cache-Control', 'no-store, private');
    }

    private function buscador(string $codigo = '', ?string $error = null, int $estado = 200)
    {
        $titulo = match ($estado) {
            404 => 'Código no encontrado',
            409 => 'Código ambiguo',
            default => 'Consulta la trazabilidad de tu producto',
        };

        return response()->view('trazabilidad.buscar', compact('codigo', 'error', 'titulo'), $estado)
            ->header('Cache-Control', 'no-store, private');
    }
}
