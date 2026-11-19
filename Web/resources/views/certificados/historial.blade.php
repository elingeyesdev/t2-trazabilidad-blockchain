@extends('layouts.app')
@section('title', 'Historial de certificados')
@section('page_title', 'Historial de certificados')
@section('content')
<p class="text-muted">Lote actual: {{ $producto->nombre }}. Cada fila corresponde a una emisión independiente.</p>
<div class="card"><div class="table-responsive"><table class="table mb-0"><thead><tr><th>Emisión</th><th>Fecha</th><th>Resultado</th><th>Antecedentes</th><th></th></tr></thead><tbody>
@forelse($certificados as $cert)
<tr><td style="min-width:180px;overflow-wrap:anywhere"><a href="{{ $ambito === 'campo' ? route('certificaciones.show', $cert) : route('certificaciones-planta.show', $cert) }}">{{ $cert->codigo_certificado ?? 'Evaluación #'.$cert->getKey() }}</a></td>
<td>{{ ($ambito === 'campo' ? $cert->fecha_certificacion : $cert->fecha_evaluacion)?->format('d/m/Y H:i:s') ?? 'No registrada' }}</td>
<td>{{ $ambito === 'campo' ? $cert->resultado : $cert->razon }}</td>
<td>{{ $cert->datos_emision ? 'Datos conservados al emitir' : 'Sin instantánea histórica' }}</td>
<td><a class="btn btn-sm btn-outline-secondary" href="{{ $ambito === 'campo' ? route('certificaciones.show', $cert) : route('certificaciones-planta.show', $cert) }}">Consultar</a></td></tr>
@empty<tr><td colspan="5" class="text-muted p-4">Todavía no hay emisiones registradas para este lote.</td></tr>@endforelse
</tbody></table></div><div class="card-footer">{{ $certificados->links() }}</div></div>
@include('certificados.partials.nueva-emision', compact('producto', 'ambito'))
@endsection
