<?php

namespace App\Services;

use App\Http\Resources\Api\IncidenteEnvioResource;
use App\Models\IncidenteEnvio;
use App\Support\UsuarioRol;
use Illuminate\Http\Request;

final class IncidenteConsultaService
{
    public function listado(Request $request)
    {
        $f = $request->validate(['estado' => ['nullable', 'in:abierto,pendiente,resuelto'],
            'q' => ['nullable', 'string', 'max:150'], 'tipo' => ['nullable', 'string', 'max:100'],
            'envio' => ['nullable', 'string', 'max:64'],
            'desde' => ['nullable', 'date_format:Y-m-d'], 'hasta' => ['nullable', 'date_format:Y-m-d', ...($request->filled('desde') ? ['after_or_equal:desde'] : [])],
            'afectado_tipo' => ['nullable', 'required_with:afectado_id', 'in:pedido_agricola,pedido_distribucion,envio_agricola,traslado,distribucion'],
            'afectado_id' => ['nullable', 'required_with:afectado_tipo', 'integer', 'min:1'],
            'page' => ['nullable', 'integer', 'min:1'], 'per_page' => ['nullable', 'integer', 'between:1,50']]);
        $referencias = app(IncidenteReferenciaService::class);
        $q = $referencias->scope(IncidenteEnvio::query(), $request->user());
        if (! empty($f['afectado_tipo'])) {
            $tipo = $f['afectado_tipo'];
            $referencias->buscar($tipo, (int) $f['afectado_id'], $request->user());
            $q->where('afectado_tipo', $tipo)->where($referencias->columna($tipo), $f['afectado_id']);
        }
        $q->when($f['estado'] ?? null, fn ($w, $v) => $w->where('estado', $v))
            ->when($f['q'] ?? null, fn ($w, $v) => $w->where(fn ($s) => $s->where('descripcion', 'like', '%'.$v.'%')->orWhere('tipo', 'like', '%'.$v.'%')->orWhere('nota_resolucion', 'like', '%'.$v.'%')))
            ->when($f['tipo'] ?? null, fn ($w, $v) => $w->where('tipo', $v))
            ->when($f['envio'] ?? null, fn ($w, $v) => $w->where('externo_envio_id', $v))
            ->when($f['desde'] ?? null, fn ($w, $v) => $w->whereDate('created_at', '>=', $v))
            ->when($f['hasta'] ?? null, fn ($w, $v) => $w->whereDate('created_at', '<=', $v));

        $pagina = $q->with(['responsable', 'reportadoPor', 'resueltoPor'])->orderByDesc('created_at')->orderByDesc('incidenteenvioid')
            ->paginate($f['per_page'] ?? 15)->withQueryString();
        $visibles = [];
        foreach (IncidenteReferenciaService::TIPOS as $tipo) {
            $columna = $referencias->columna($tipo);
            $ids = $pagina->getCollection()->where('afectado_tipo', $tipo)->pluck($columna)->filter()->unique();
            if ($ids->isNotEmpty()) {
                $fuente = $referencias->consulta($tipo, $request->user())->whereKey($ids);
                $visibles[$tipo] = $fuente->pluck($fuente->getModel()->getKeyName())->map(fn ($id) => (int) $id)->all();
            }
        }

        return $pagina->through(function ($incidente) use ($request, $referencias, $visibles) {
            $tipo = $incidente->afectado_tipo;
            $id = $tipo ? $incidente->{$referencias->columna($tipo)} : null;
            $referencia = $id && in_array((int) $id, $visibles[$tipo] ?? [], true) ? ['tipo' => $tipo, 'id' => (int) $id] : null;
            $incidente->setRelation('consultaReferencia', $referencia);
            $incidente->setRelation('consultaResolver', UsuarioRol::puedeOperar($request->user())
                && $referencias->puedeAtenderTipo((string) $tipo, $request->user())
                && $request->user()->can('incidentes.resolve') && $incidente->responsable_usuarioid !== null);

            return (new IncidenteEnvioResource($incidente))->resolve($request);
        });
    }
}
