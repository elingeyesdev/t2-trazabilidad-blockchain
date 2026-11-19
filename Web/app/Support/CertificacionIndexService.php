<?php

namespace App\Support;

use App\Models\CertificacionLote;
use App\Models\EvaluacionFinalLoteProduccion;
use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Models\Usuario;
use Illuminate\Support\Collection;
use App\Support\UsuarioRol;

class CertificacionIndexService
{
    public function __construct(
        private LoteProduccionTransformacionService $transformacion
    ) {}

    /** @return array{pendientes: Collection, evaluaciones: Collection, stats: array<string, int>, ambito: string, filtros: array<string, string>} */
    public function datosPlanta(array $filtros = []): array
    {
        $q = mb_strtolower(trim($filtros['q'] ?? ''));
        $producto = mb_strtolower(trim($filtros['producto'] ?? ''));
        $resultado = trim($filtros['resultado'] ?? '');
        $desde = trim($filtros['desde'] ?? '');
        $hasta = trim($filtros['hasta'] ?? '');

        $coincideLote = function (LoteProduccionPedido $lote) use ($q, $producto): bool {
            if ($q !== '') {
                $texto = mb_strtolower(implode(' ', array_filter([
                    $lote->nombre,
                    $lote->codigo_lote,
                    $lote->producto,
                    $lote->plantillaTransformacion?->nombre,
                ])));
                if (! str_contains($texto, $q)) {
                    return false;
                }
            }
            if ($producto !== '') {
                $prod = mb_strtolower((string) ($lote->producto ?? ''));
                $nombre = mb_strtolower((string) ($lote->nombre ?? ''));
                if (! str_contains($prod, $producto) && ! str_contains($nombre, $producto)) {
                    return false;
                }
            }

            return true;
        };

        $usuario = auth()->user();
        $lotes = ($usuario ? CertificadoAcceso::scopePlanta(LoteProduccionPedido::query(), $usuario) : LoteProduccionPedido::whereRaw('1 = 0'))
            ->with([
                'evaluacionesFinales',
                'plantillaTransformacion',
                'pedido',
                'unidadMedida',
            ])
            ->orderByDesc('loteproduccionpedidoid')
            ->get();

        $pendientes = $lotes->filter(function (LoteProduccionPedido $lote) use ($coincideLote) {
            return $this->transformacion->transformacionCompleta($lote)
                && $lote->evaluacionesFinales->isEmpty()
                && $coincideLote($lote);
        })->values();

        $evaluacionesQuery = EvaluacionFinalLoteProduccion::query()
            ->with([
                'loteProduccionPedido.pedido',
                'loteProduccionPedido.plantillaTransformacion',
                'inspector',
            ])
            ->whereHas('loteProduccionPedido', fn ($q) => $usuario ? CertificadoAcceso::scopePlanta($q, $usuario) : $q->whereRaw('1 = 0'))
            ->orderByDesc('fecha_evaluacion')->orderByDesc('evaluacionfinalloteid');

        if ($resultado === 'certificado') {
            $evaluacionesQuery->where('razon', EvaluacionFinalLoteProduccion::RAZON_CERTIFICADO);
        } elseif ($resultado === 'no_conforme') {
            $evaluacionesQuery->where('razon', EvaluacionFinalLoteProduccion::RAZON_NO_CONFORME);
        }

        if ($desde !== '') {
            $evaluacionesQuery->whereDate('fecha_evaluacion', '>=', $desde);
        }
        if ($hasta !== '') {
            $evaluacionesQuery->whereDate('fecha_evaluacion', '<=', $hasta);
        }

        if ($q !== '' || $producto !== '') {
            $evaluacionesQuery->whereHas('loteProduccionPedido', function ($lq) use ($q, $producto) {
                if ($q !== '') {
                    $term = '%'.$q.'%';
                    $lq->where(function ($w) use ($term) {
                        $w->whereRaw('LOWER(nombre) LIKE ?', [$term])
                            ->orWhereRaw('LOWER(codigo_lote) LIKE ?', [$term])
                            ->orWhereRaw('LOWER(producto) LIKE ?', [$term]);
                    });
                }
                if ($producto !== '') {
                    $termProd = '%'.$producto.'%';
                    $lq->where(function ($w) use ($termProd) {
                        $w->whereRaw('LOWER(producto) LIKE ?', [$termProd])
                            ->orWhereRaw('LOWER(nombre) LIKE ?', [$termProd]);
                    });
                }
            });
        }

        $evaluaciones = $evaluacionesQuery->limit(50)->get();

        $certificadosOk = $lotes->filter(function (LoteProduccionPedido $lote) {
            $ultima = $lote->evaluacionesFinales->sortBy([['fecha_evaluacion', 'desc'], ['evaluacionfinalloteid', 'desc']])->first();

            return $ultima && $ultima->esCertificado();
        });

        $noConformes = $lotes->filter(function (LoteProduccionPedido $lote) {
            $ultima = $lote->evaluacionesFinales->sortBy([['fecha_evaluacion', 'desc'], ['evaluacionfinalloteid', 'desc']])->first();

            return $ultima && $ultima->esNoConforme();
        });

        return [
            'ambito' => 'planta',
            'pendientes' => $pendientes,
            'evaluaciones' => $evaluaciones,
            'stats' => [
                'pendientes' => $pendientes->count(),
                'certificados' => $certificadosOk->count(),
                'no_conformes' => $noConformes->count(),
                'total_lotes' => $lotes->count(),
            ],
            'filtros' => [
                'q' => $filtros['q'] ?? '',
                'producto' => $filtros['producto'] ?? '',
                'resultado' => $resultado,
                'desde' => $desde,
                'hasta' => $hasta,
            ],
        ];
    }

    /** @return array{pendientes: Collection, evaluaciones: Collection, stats: array<string, int>, ambito: string} */
    public function datosCampo(?Usuario $user = null): array
    {
        $estadoCosechado = EstadoLoteCatalogo::idsPorSlugs(['cosechado']);

        $query = Lote::query()
            ->with(['cultivo', 'estadoTipo', 'usuario', 'producciones'])
            ->whereHas('producciones')
            ->orderByDesc('loteid');

        if ($user && UsuarioRol::debeAcotarPorAsignacion($user)) {
            $query->where('usuarioid', (int) $user->usuarioid);
        } elseif ($user && UsuarioRol::esJefeAgricultor($user) && ! UsuarioRol::esAdminGlobal($user)) {
            $query->whereIn('usuarioid', UsuarioRol::idsUsuariosBajoJefeAgricultor($user));
        }

        if ($estadoCosechado !== []) {
            $query->whereIn('estadolotetipoid', $estadoCosechado);
        }

        $lotesCosechados = $query->get();

        $idsEvaluados = CertificacionLote::query()
            ->when($user && UsuarioRol::debeAcotarPorAsignacion($user), function ($q) use ($user) {
                $q->whereHas('lote', fn ($l) => $l->where('usuarioid', (int) $user->usuarioid));
            })
            ->when($user && UsuarioRol::esJefeAgricultor($user) && ! UsuarioRol::esAdminGlobal($user), function ($q) use ($user) {
                $q->whereHas('lote', fn ($l) => $l->whereIn('usuarioid', UsuarioRol::idsUsuariosBajoJefeAgricultor($user)));
            })
            ->pluck('loteid')
            ->unique()
            ->all();

        $pendientes = $lotesCosechados
            ->filter(fn (Lote $l) => ! in_array($l->loteid, $idsEvaluados, true))
            ->values();

        $evaluacionesQuery = CertificacionLote::query()
            ->with(['lote.cultivo', 'usuario'])
            ->orderByDesc('fecha_certificacion')->orderByDesc('certificacionid');

        if ($user && UsuarioRol::debeAcotarPorAsignacion($user)) {
            $evaluacionesQuery->whereHas('lote', fn ($l) => $l->where('usuarioid', (int) $user->usuarioid));
        } elseif ($user && UsuarioRol::esJefeAgricultor($user) && ! UsuarioRol::esAdminGlobal($user)) {
            $evaluacionesQuery->whereHas('lote', fn ($l) => $l->whereIn('usuarioid', UsuarioRol::idsUsuariosBajoJefeAgricultor($user)));
        }

        $evaluaciones = (clone $evaluacionesQuery)->limit(20)->get();

        $ultimas = (clone $evaluacionesQuery)->without(['lote', 'usuario'])->get(['certificacionid', 'loteid', 'resultado'])->unique('loteid');
        $totalCertificados = $ultimas->where('resultado', CertificacionLote::RAZON_CERTIFICADO)->count();
        $totalNoConformes = $ultimas->where('resultado', CertificacionLote::RAZON_NO_CONFORME)->count();

        return [
            'ambito' => 'campo',
            'pendientes' => $pendientes,
            'evaluaciones' => $evaluaciones,
            'stats' => [
                'pendientes' => $pendientes->count(),
                'certificados' => $totalCertificados,
                'no_conformes' => $totalNoConformes,
                'total_lotes' => $lotesCosechados->count(),
            ],
        ];
    }
}
