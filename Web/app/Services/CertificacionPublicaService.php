<?php

namespace App\Services;

use App\Models\CertificacionLote;
use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Collection;

/** Read-only, explicitly public projection of linked historical emissions. */
class CertificacionPublicaService
{
    public function proyectar(Collection $lotesCampo, Collection $lotesPlanta): array
    {
        $campo = new EloquentCollection($lotesCampo->filter(fn ($lote) => $lote instanceof Lote)
            ->unique(fn (Lote $lote) => $lote->getKey())->values()->all());
        $planta = new EloquentCollection($lotesPlanta->filter(fn ($lote) => $lote instanceof LoteProduccionPedido)
            ->unique(fn (LoteProduccionPedido $lote) => $lote->getKey())->values()->all());
        // Batch-load missing relations; never emit or synchronize a certificate on this path.
        $campo->loadMissing('certificaciones');
        $planta->loadMissing('evaluacionesFinales');
        $filas = collect();
        foreach ($campo as $lote) {
            foreach ($lote->certificaciones as $emision) {
                if ((string) $emision->loteid === (string) $lote->getKey()) {
                    $filas->push(['ambito' => 'agricola', 'lote' => $lote, 'emision' => $emision,
                        'fecha' => $emision->fecha_certificacion]);
                }
            }
        }
        foreach ($planta as $lote) {
            foreach ($lote->evaluacionesFinales as $emision) {
                if ((string) $emision->loteproduccionpedidoid === (string) $lote->getKey()) {
                    $filas->push(['ambito' => 'planta', 'lote' => $lote, 'emision' => $emision,
                        'fecha' => $emision->fecha_evaluacion]);
                }
            }
        }
        $filas = $filas->unique(fn (array $fila) => $fila['ambito'].':'.$fila['emision']->getKey())
            ->sort(function (array $a, array $b): int {
                return [$this->fecha($a['fecha']) ?? '', $a['ambito'], (int) $a['emision']->getKey()]
                    <=> [$this->fecha($b['fecha']) ?? '', $b['ambito'], (int) $b['emision']->getKey()];
            })->values();

        $emisiones = [];
        $registros = [];
        foreach ($filas as $fila) {
            $emision = $fila['emision'];
            $referencia = [
                'ambito' => $fila['ambito'],
                'codigo_lote' => $fila['lote'] instanceof Lote
                    ? $fila['lote']->codigo_trazabilidad : $fila['lote']->codigo_lote,
                'codigo_certificado' => $emision->codigo_certificado,
            ];
            $emisiones[] = [
                ...$referencia,
                'fecha_emision' => $this->fecha($fila['fecha']),
                'resultado' => $this->resultado($emision instanceof CertificacionLote ? $emision->resultado : $emision->razon),
                // Neither certificate model defines expiry, revocation or a current-emission rule.
                'vigencia' => 'no_determinada',
            ];
            if ($emision instanceof CertificacionLote && $this->tieneRegistroBlockchain($emision)) {
                $registros[] = [
                    ...$referencia,
                    'estado_registrado' => $this->estadoBlockchain($emision->blockchain_estado),
                    'fuente' => 'registro_local',
                    'verificado_en_vivo' => false,
                    'confirmacion_registrada' => $emision->blockchainConfirmada(),
                    // blockchain_hash fingerprints the canonical payload, not the PDF or a block.
                    'hash_payload' => $emision->blockchain_hash,
                    'hash_documento' => null,
                    'hash_transaccion' => $emision->blockchain_txid,
                    'hash_bloque' => null,
                    'red' => null,
                    'explorador_url' => null,
                    'fecha_envio_registrada' => $this->fecha($emision->blockchain_enviado_en),
                    'fecha_confirmacion_registrada' => $this->fecha($emision->blockchain_certificado_en),
                    // No dedicated last-provider-check timestamp is persisted by the current model.
                    'ultima_comprobacion_en' => null,
                ];
            }
        }

        return [
            'certificaciones' => [
                'estado' => $emisiones === [] ? 'sin_certificacion_registrada' : 'con_emisiones_registradas',
                'emisiones' => $emisiones,
            ],
            'blockchain' => [
                'estado' => $registros === [] ? 'sin_respaldo_registrado' : 'con_registros',
                'registros' => $registros,
            ],
        ];
    }

    private function tieneRegistroBlockchain(CertificacionLote $emision): bool
    {
        return filled($emision->blockchain_estado) || filled($emision->blockchain_hash)
            || filled($emision->blockchain_txid) || $emision->blockchain_enviado_en !== null
            || $emision->blockchain_certificado_en !== null;
    }

    private function resultado(?string $resultado): ?string
    {
        // Historical rows can predate enum validation; free-form inspection narratives remain private.
        return in_array($resultado, CertificacionLote::RAZONES, true) ? $resultado : null;
    }

    private function estadoBlockchain(?string $estado): ?string
    {
        return in_array($estado, [CertificacionLote::BLOCKCHAIN_PENDIENTE, CertificacionLote::BLOCKCHAIN_CERTIFICADA,
            CertificacionLote::BLOCKCHAIN_RECHAZADA, CertificacionLote::BLOCKCHAIN_ERROR,
            CertificacionLote::BLOCKCHAIN_OMITIDA, 'confirmado'], true) ? $estado : null;
    }

    private function fecha(mixed $fecha): ?string
    {
        return $fecha instanceof \DateTimeInterface ? $fecha->format(\DateTimeInterface::ATOM) : null;
    }
}
