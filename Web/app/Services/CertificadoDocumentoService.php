<?php

namespace App\Services;

use Barryvdh\DomPDF\Facade\Pdf;

class CertificadoDocumentoService
{
    public const VERSION = 1;

    public function generar(array $datos): string
    {
        return Pdf::loadView('certificados.documento-v1', ['datos' => $datos])
            ->setOption('isRemoteEnabled', false)->setPaper('a4')->output();
    }
}
