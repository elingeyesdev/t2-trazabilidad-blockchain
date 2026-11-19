<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\RecepcionQrEnvio;
use App\Services\EnvioMovilConsultaService;
use App\Services\EnvioRecepcionQrService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class EnvioMovilController extends Controller
{
    public function index(Request $request, string $tipo, EnvioMovilConsultaService $consulta)
    {
        $data = $request->validate(['per_page' => ['sometimes', 'integer', 'between:1,50'], 'page' => ['sometimes', 'integer', 'min:1'], 'estado' => ['sometimes', 'string', 'max:60']]);
        $query = $consulta->consulta($tipo, $request->user());
        $pagina = $query->when(isset($data['estado']), fn ($q) => $q->where('estado', $data['estado']))
            ->orderByDesc($query->getModel()->getKeyName())->paginate($data['per_page'] ?? 15)->withQueryString();

        return response()->json(['data' => $pagina->getCollection()->map(fn ($e) => $consulta->datos($e, $request->user())),
            'links' => ['prev' => $pagina->previousPageUrl(), 'next' => $pagina->nextPageUrl()],
            'meta' => ['current_page' => $pagina->currentPage(), 'per_page' => $pagina->perPage(), 'total' => $pagina->total()]]);
    }

    public function show(Request $request, string $tipo, int $envio, EnvioMovilConsultaService $consulta)
    {
        return ['data' => $consulta->datos($consulta->buscar($tipo, $envio, $request->user()), $request->user())];
    }

    public function codigos(Request $request, string $tipo, int $envio, EnvioMovilConsultaService $consulta, EnvioRecepcionQrService $service)
    {
        $operacion = $consulta->buscar($tipo, $envio, $request->user());
        // La emisión no confirma la entrega. Únicamente el conductor asignado o destinatario obtiene el secreto.
        $destino = (new RecepcionQrEnvio)->forceFill(['destinatario_usuarioid' => $request->user()->getKey()]);
        abort_unless(\App\Support\ViajeAcceso::esConductorAsignado($request->user(), $operacion->transportista_usuarioid)
            || $service->puedeConfirmar($destino, $request->user(), $operacion), 403);
        $qrs = $service->emitir($operacion);
        $qrs = array_values(array_filter($qrs, fn ($qr) => (int) $operacion->transportista_usuarioid === (int) $request->user()->getKey()
            || $service->puedeConfirmar($qr, $request->user(), $operacion)));
        abort_if($qrs === [], 403);

        return ['data' => array_map(fn ($qr) => ['recepcion_id' => $qr->getKey(), 'destinatario_id' => $qr->destinatario_usuarioid,
            'url' => $qr->utilizado_en ? null : $service->url($qr), 'utilizado' => $qr->utilizado_en !== null], $qrs)];
    }

    public function resolver(Request $request, EnvioRecepcionQrService $service, EnvioMovilConsultaService $consulta)
    {
        $data = $request->validate(['codigo' => ['required', 'string', 'max:2048']]);
        $qr = $service->resolver($data['codigo']);
        $envio = $service->autorizarConsulta($qr, $request->user());

        return ['data' => ['recepcion_id' => $qr->getKey(), 'utilizado' => $qr->utilizado_en !== null,
            'puede_confirmar' => ! $qr->utilizado_en && $service->puedeConfirmar($qr, $request->user(), $envio),
            'envio' => $consulta->datos($envio, $request->user())]];
    }

    public function confirmar(Request $request, string $tipo, int $envio, EnvioRecepcionQrService $service, EnvioMovilConsultaService $consulta)
    {
        $operacion = $consulta->buscar($tipo, $envio, $request->user());
        $data = $request->validate(['codigo' => ['required', 'string', 'max:2048'], 'imagen_firma' => ['required', 'string', 'max:1400000'],
            'lineas' => ['required', 'array', 'min:1', 'max:500'], 'lineas.*' => ['required', 'array'],
            'firmante_usuarioid' => ['missing'], 'usuarioid' => ['missing'], 'fecha' => ['missing'], 'estado' => ['missing']]);
        $qr = $service->resolver($data['codigo']);
        abort_unless((int) ($tipo === 'agricola' ? $qr->envioasignacionmultipleid : $qr->rutadistribucionid) === (int) $operacion->getKey()
            && $consulta->tipo($service->operacion($qr)) === $tipo, 404);
        try {
            $qr = $service->confirmar($qr, $request->user(), $data['lineas'], $data['imagen_firma']);
        } catch (\InvalidArgumentException $e) {
            throw ValidationException::withMessages(['recepcion' => $e->getMessage()]);
        }

        return response()->json(['data' => $this->datosRecepcion($qr)], 201);
    }

    public function recepcion(Request $request, int $recepcion, EnvioRecepcionQrService $service)
    {
        $qr = RecepcionQrEnvio::findOrFail($recepcion);
        $service->autorizarConsulta($qr, $request->user());
        abort_unless($qr->utilizado_en && $qr->datos_recepcion, 404);

        return ['data' => $this->datosRecepcion($qr)];
    }

    public function firma(Request $request, int $recepcion, EnvioRecepcionQrService $service)
    {
        $qr = RecepcionQrEnvio::findOrFail($recepcion);
        $service->autorizarConsulta($qr, $request->user());
        abort_unless($qr->utilizado_en && $qr->firma_path && Storage::disk('local')->exists($qr->firma_path), 404);

        return response(Storage::disk('local')->get($qr->firma_path), 200, ['Content-Type' => 'image/png', 'Cache-Control' => 'private, no-store', 'X-Content-Type-Options' => 'nosniff']);
    }

    public function comprobante(Request $request, int $recepcion, EnvioRecepcionQrService $service)
    {
        $qr = RecepcionQrEnvio::findOrFail($recepcion);
        $service->autorizarConsulta($qr, $request->user());
        abort_unless($qr->utilizado_en && $qr->datos_recepcion && $qr->firma_path && Storage::disk('local')->exists($qr->firma_path), 404);
        $datos = $qr->datos_recepcion;
        $firma = 'data:image/png;base64,'.base64_encode(Storage::disk('local')->get($qr->firma_path));

        // Generación bajo demanda: un fallo de PDF no deshace ni repite una recepción confirmada.
        return Pdf::loadView('recepcion.comprobante', ['datos' => $datos, 'firma' => $firma, 'numero' => $qr->getKey()])
            ->stream('recepcion-'.$qr->getKey().'.pdf')->header('Cache-Control', 'private, no-store');
    }

    private function datosRecepcion(RecepcionQrEnvio $qr): array
    {
        return ['id' => $qr->getKey()] + $qr->datos_recepcion + ['firma_url' => url('/api/recepciones-envio/'.$qr->getKey().'/firma'),
            'comprobante_url' => url('/api/recepciones-envio/'.$qr->getKey().'/comprobante')];
    }
}
