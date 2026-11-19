<?php

namespace App\Services;

use App\Models\EnvioAsignacionMultiple;
use App\Models\RecepcionQrEnvio;
use App\Models\RutaDistribucion;
use App\Models\Usuario;
use Symfony\Component\HttpKernel\Exception\HttpException;

class EntregaWebPresentacionService
{
    public function seguimientoUrl(EnvioAsignacionMultiple|RutaDistribucion|null $envio, ?Usuario $user): ?string
    {
        if (! $envio || ! $user) {
            return null;
        }
        $consulta = app(EnvioMovilConsultaService::class);
        $tipo = $consulta->tipo($envio);
        if (! $consulta->permiso($tipo, $user) || ! $consulta->consulta($tipo, $user)->whereKey($envio->getKey())->exists()) {
            return null;
        }

        return route('envios.seguimiento', ['tipo' => $tipo, 'envio' => $envio->getKey()]);
    }

    /** Solo consulta recepciones persistidas: nunca emite ni consume códigos. */
    public function comprobantes(EnvioAsignacionMultiple|RutaDistribucion|null $envio, ?Usuario $user): array
    {
        if (! $envio || ! $user || ! $this->seguimientoUrl($envio, $user)) {
            return [];
        }
        $codigos = RecepcionQrEnvio::where($envio instanceof EnvioAsignacionMultiple ? 'envioasignacionmultipleid' : 'rutadistribucionid', $envio->getKey())
            ->whereNotNull('utilizado_en')->whereNotNull('firma_path')->whereNotNull('datos_recepcion')->orderBy('recepcionqrenvioid')->get();
        $resultado = [];
        foreach ($codigos as $codigo) {
            try {
                app(EnvioRecepcionQrService::class)->autorizarConsulta($codigo, $user);
                $resultado[] = ['id' => $codigo->getKey(), 'fecha' => $codigo->utilizado_en,
                    'url' => route('recepcion.comprobante', $codigo->getKey())];
            } catch (HttpException $e) {
                if (! in_array($e->getStatusCode(), [403, 404], true)) {
                    throw $e;
                }
            }
        }

        return $resultado;
    }
}
