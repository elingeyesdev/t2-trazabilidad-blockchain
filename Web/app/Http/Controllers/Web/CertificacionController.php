<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\CertificacionLote;
use App\Models\EstadoLoteTipo;
use App\Models\HistorialEstadoLote;
use App\Models\Lote;
use App\Services\Blockchain\CertificacionBlockchainService;
use App\Support\CertificacionIndexService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

class CertificacionController extends Controller
{
    public function __construct(
        private CertificacionIndexService $indexService,
        private CertificacionBlockchainService $blockchainService,
    ) {}

    public function index(Request $request): View|RedirectResponse
    {
        $datos = $this->indexService->datosCampo($request->user());

        return view('certificaciones.index', [
            'lotesPendientes' => $datos['pendientes'],
            'certificados' => $datos['evaluaciones'],
            'stats' => $datos['stats'],
        ]);
    }

    public function store(\App\Http\Requests\EmisionCertificadoRequest $request): RedirectResponse
    {
        $validated = $request->validate([
            'solicitud_id' => ['nullable', 'uuid'],
            'loteid'        => ['required', 'integer', 'exists:lote,loteid'],
            'resultado'     => ['nullable', 'string', Rule::in(CertificacionLote::RAZONES)],
            'observaciones' => ['nullable', 'string', 'max:1000'],
            'recomendaciones' => ['nullable', 'string', 'max:2000'],
        ]);

        $resultado = $validated['resultado'] ?? CertificacionLote::RAZON_CERTIFICADO;

        if ($resultado === CertificacionLote::RAZON_NO_CONFORME && blank($validated['observaciones'] ?? null)) {
            return back()
                ->withErrors(['observaciones' => 'Indique el motivo del no conforme (daños, plagas, calidad, etc.).'])
                ->withInput();
        }

        $this->evaluarLote(
            (int) $validated['loteid'],
            $resultado,
            $validated['observaciones'] ?? null,
            $validated['recomendaciones'] ?? null,
            $validated['solicitud_id'] ?? null
        );

        $lote = Lote::findOrFail((int) $validated['loteid']);

        $returnUrl = $this->validReturnUrl($request->input('return'));
        if ($returnUrl) {
            return redirect($returnUrl);
        }

        if ($request->boolean('from_trazabilidad')) {
            return redirect()->route('lotes.trazabilidad', $lote);
        }

        return redirect()->route('certificaciones.index');
    }

    private function validReturnUrl(mixed $return): ?string
    {
        if (! is_string($return) || trim($return) === '') {
            return null;
        }

        $return = trim($return);
        if (str_starts_with($return, '/')) {
            return $return;
        }

        $appUrl = rtrim((string) config('app.url'), '/');
        if (str_starts_with($return, $appUrl)) {
            return $return;
        }

        if (preg_match('#^https?://[^/]+(/lotes/\d+/trazabilidad(?:\?.*)?)$#', $return, $m)) {
            return $m[1];
        }

        return null;
    }

    public function storeBatch(Request $request): RedirectResponse
    {
        $request->validate([
            'solicitud_id' => ['nullable', 'uuid'],
            'lotes'         => ['required', 'array', 'min:1'],
            'lotes.*'       => ['integer', 'exists:lote,loteid'],
            'observaciones' => ['nullable', 'string', 'max:1000'],
        ]);

        $count = 0;
        foreach ($request->lotes as $loteid) {
            $this->evaluarLote((int) $loteid, CertificacionLote::RAZON_CERTIFICADO, $request->observaciones, null,
                $request->input('solicitud_id') ? (string) \Ramsey\Uuid\Uuid::uuid5($request->input('solicitud_id'), (string) $loteid) : null);
            $count++;
        }

        return redirect()->route('certificaciones.index');
    }

    public function show(CertificacionLote $certificacion): View
    {
        return app(\App\Http\Controllers\CertificadoHistorialController::class)->campo(request(), $certificacion);
    }

    public function sincronizarBlockchain(CertificacionLote $certificacion): RedirectResponse
    {
        abort_unless($certificacion->lote && \App\Support\CertificadoAcceso::campo(auth()->user(), $certificacion->lote), 404);
        if (! $certificacion->esCertificado()) {
            return back()->with('warning', 'Solo las certificaciones conformes pueden sincronizarse con blockchain.');
        }

        if (! in_array($certificacion->blockchain_estado, [
            CertificacionLote::BLOCKCHAIN_PENDIENTE,
            CertificacionLote::BLOCKCHAIN_ERROR,
        ], true)) {
            return back()->with('info', 'Esta certificación no tiene una solicitud blockchain pendiente para sincronizar.');
        }

        $this->blockchainService->enviar((int) $certificacion->certificacionid);
        $certificacion->refresh();

        return match ($certificacion->blockchain_estado) {
            CertificacionLote::BLOCKCHAIN_CERTIFICADA => back()->with('success', 'Certificación blockchain actualizada. Tx ID recibido.'),
            CertificacionLote::BLOCKCHAIN_RECHAZADA => back()->with('warning', 'La solicitud blockchain fue rechazada.'),
            CertificacionLote::BLOCKCHAIN_ERROR => back()->with('error', 'No se pudo sincronizar con blockchain: '.$certificacion->blockchain_error),
            default => back()->with('info', 'La solicitud blockchain continúa pendiente de aprobación.'),
        };
    }

    private function evaluarLote(int $loteid, string $resultado, ?string $observaciones, ?string $recomendaciones = null, ?string $solicitudId = null): void
    {
        app(\App\Services\CertificadoEmisionService::class)->emitirCampo(auth()->user(), Lote::findOrFail($loteid), [
            'resultado' => $resultado, 'observaciones' => $observaciones, 'recomendaciones' => $recomendaciones, 'solicitud_id' => $solicitudId,
        ]);
    }
}
