<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\EnvioAsignacionMultiple;
use App\Models\RecepcionQrEnvio;
use App\Models\RutaDistribucion;
use App\Services\EnvioMovilConsultaService;
use App\Services\EnvioRecepcionQrService;
use App\Services\RecepcionQrFirmaService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class RecepcionQrPublicaController extends Controller
{
    public function __construct(
        private readonly RecepcionQrFirmaService $recepcionQr,
    ) {}

    public function desdePlanta(Request $request, int $asignacion, EnvioMovilConsultaService $consulta, EnvioRecepcionQrService $service): View
    {
        $operacion = $this->autorizarRecepcionPlanta($request, $asignacion, $consulta, $service);
        $qr = RecepcionQrEnvio::where('envioasignacionmultipleid', $asignacion)->first();
        abort_unless($qr?->utilizado_en || $service->listaParaRecepcion($operacion), 409,
            'El envío todavía no está listo para recepción: faltan llegada, revisión de incidentes o firma del transportista.');
        $qr = $service->emitir($operacion)[0];

        return view('recepcion.confirmar', [
            'qr' => $qr, 'token' => $qr->token,
            'envio' => $consulta->datos($operacion, $request->user()),
            'puedeConfirmar' => ! $qr->utilizado_en && $service->listaParaRecepcion($operacion),
            'accionFirma' => route('recepcion.planta.confirmar', $asignacion, absolute: false),
            'desdeDashboard' => true,
        ]);
    }

    public function confirmarEnPlanta(Request $request, int $asignacion, EnvioMovilConsultaService $consulta, EnvioRecepcionQrService $service): RedirectResponse
    {
        $operacion = $this->autorizarRecepcionPlanta($request, $asignacion, $consulta, $service);
        $qr = $service->emitir($operacion)[0];
        $this->confirmarConLineas($request, $qr);

        return redirect()->to(route('recepcion.planta', $asignacion, absolute: false))
            ->with('exito', 'Recepción registrada correctamente.');
    }

    private function autorizarRecepcionPlanta(Request $request, int $asignacion, EnvioMovilConsultaService $consulta, EnvioRecepcionQrService $service): EnvioAsignacionMultiple
    {
        $operacion = $consulta->buscar('agricola', $asignacion, $request->user());
        abort_unless($service->puedeConfirmar(new RecepcionQrEnvio, $request->user(), $operacion), 403);

        return $operacion;
    }

    private function confirmarConLineas(Request $request, RecepcionQrEnvio $qr): void
    {
        $data = $request->validate(['imagen_firma' => ['required', 'string', 'max:1400000'], 'lineas' => ['required', 'array', 'min:1', 'max:500'], 'lineas.*' => ['required', 'array'],
            'firmante_usuarioid' => ['missing'], 'usuarioid' => ['missing'], 'fecha' => ['missing'], 'estado' => ['missing']]);
        try {
            app(EnvioRecepcionQrService::class)->confirmar($qr, $request->user(), $data['lineas'], $data['imagen_firma']);
        } catch (\InvalidArgumentException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['recepcion' => $e->getMessage()]);
        }
    }

    public function show(Request $request, string $token): View|RedirectResponse
    {
        $qr = $this->recepcionQr->resolverPorToken($token);
        $operacion = $this->recepcionQr->resolverOperacion($qr);
        $operacion->loadMissing('firmaTransportista', 'firmaRecepcion');
        $usuario = $request->user();

        // Los enlaces previos siguen identificando el envío, pero se reciben con el código propio.
        if (! $qr->clave_operacion && $usuario) {
            $consulta = app(\App\Services\EnvioMovilConsultaService::class);
            $tieneLineas = $operacion instanceof EnvioAsignacionMultiple
                ? $operacion->pedido?->detalles()->exists()
                : ($operacion->esTrasladoPlantaMayorista() ? $operacion->detallesTraslado()->exists() : $operacion->pedidos()->exists());
            if ($tieneLineas && $consulta->permiso($consulta->tipo($operacion), $usuario)) {
                $service = app(\App\Services\EnvioRecepcionQrService::class);
                $service->autorizarConsulta($qr, $usuario);
                $simulado = (new \App\Models\RecepcionQrEnvio)->forceFill(['destinatario_usuarioid' => $usuario->getKey()]);
                if ($service->puedeConfirmar($simulado, $usuario, $operacion)) {
                    foreach ($service->emitir($operacion) as $propio) {
                        if ($service->puedeConfirmar($propio, $usuario, $operacion)) {
                            return redirect()->route('recepcion.publica', $propio->token);
                        }
                    }
                }
            }
        }

        if ($qr->clave_operacion && $usuario) {
            $service = app(\App\Services\EnvioRecepcionQrService::class);
            $operacion = $service->autorizarConsulta($qr, $usuario);
            $consulta = app(\App\Services\EnvioMovilConsultaService::class);
            return view('recepcion.confirmar', ['qr' => $qr, 'token' => $token,
                'envio' => $consulta->datos($operacion, $usuario),
                'puedeConfirmar' => $service->puedeConfirmar($qr, $usuario, $operacion)]);
        }

        // Tras iniciar sesión, el receptor vuelve a esta misma pantalla para firmar.
        if ($usuario === null) {
            $request->session()->put('url.intended', $request->fullUrl());
        }

        $titulo = 'Firma de recepción';
        $codigo = $operacion instanceof RutaDistribucion
            ? ($operacion->codigo ?? 'Ruta #'.$operacion->rutadistribucionid)
            : ($operacion->externo_envio_id ?? 'Envío #'.$operacion->envioasignacionmultipleid);

        return view('recepcion.publica', [
            'token' => $token,
            'titulo' => $titulo,
            'codigo' => $codigo,
            'yaFirmado' => $this->recepcionQr->recepcionFirmada($operacion),
            'sinFirmaTransportista' => $operacion->firmaTransportista === null,
            'requiereSesion' => $usuario === null,
            // MAY-14: el mayorista indica lo que realmente recibió por línea.
            'lineasTraslado' => $usuario && $this->recepcionQr->esReceptorAutorizado($operacion, $usuario) && $operacion instanceof RutaDistribucion && $operacion->esTrasladoPlantaMayorista()
                ? $operacion->detallesTraslado()->get()
                : collect(),
            'puedeFirmar' => $this->recepcionQr->esReceptorAutorizado($operacion, $usuario),
            'usuario' => $usuario,
        ]);
    }

    public function firmar(Request $request, string $token): RedirectResponse|JsonResponse
    {
        $qr = $this->recepcionQr->resolverPorToken($token);
        $operacion = $this->recepcionQr->resolverOperacion($qr);
        if (! $qr->clave_operacion && ($operacion instanceof EnvioAsignacionMultiple
            ? $operacion->pedido?->detalles()->exists()
            : ($operacion->esTrasladoPlantaMayorista() ? $operacion->detallesTraslado()->exists() : $operacion->pedidos()->exists()))) {
            throw \Illuminate\Validation\ValidationException::withMessages(['codigo' => 'Abra el enlace de recepción para utilizar el código específico del destinatario.']);
        }
        if ($qr->clave_operacion) {
            $this->confirmarConLineas($request, $qr);
            return $request->expectsJson()
                ? response()->json(['mensaje' => 'Recepción registrada correctamente.'])
                : redirect()->route('recepcion.publica', $token)->with('exito', 'Recepción registrada correctamente.');
        }
        $validated = $request->validate([
            'imagen_firma' => ['required', 'string'],
            'recepcion' => ['nullable', 'array'],
            'recepcion.*.recibido' => ['nullable', 'numeric', 'min:0'],
            'recepcion.*.motivo' => ['nullable', 'string', 'max:255'],
        ]);

        try {
            $this->recepcionQr->guardarFirmaRecepcionConCuenta(
                $token,
                $request->user(),
                $validated['imagen_firma'],
                $validated['recepcion'] ?? [],
            );
        } catch (\InvalidArgumentException $e) {
            if ($request->expectsJson()) {
                return response()->json(['mensaje' => $e->getMessage()], 422);
            }

            return back()->withInput()->withErrors(['firma' => $e->getMessage()]);
        }

        if ($request->expectsJson()) {
            return response()->json(['mensaje' => 'Firma de recepción registrada correctamente.']);
        }

        return redirect()->route('recepcion.publica', $token)
            ->with('exito', 'Firma de recepción registrada correctamente.');
    }
}
