@props(['lote'])
@php
    $estado = $lote->estadoTipo->nombre ?? 'Sin estado';
@endphp
<div class="d-flex gap-2 align-items-center">
    <a class="btn btn-sm" href="{{ route('lotes.show', $lote) }}" aria-label="Ver detalle de {{ $lote->nombre }}"><i class="ti ti-eye me-1" aria-hidden="true"></i>Ver detalle</a>
    <div class="dropdown">
        <button class="btn btn-sm dropdown-toggle" type="button" data-bs-toggle="dropdown" data-bs-boundary="viewport" aria-expanded="false" aria-label="Acciones de {{ $lote->nombre }}">Acciones</button>
        <div class="dropdown-menu dropdown-menu-end">
            <a class="dropdown-item" href="{{ route('lotes.trazabilidad', $lote) }}"><i class="ti ti-route me-2" aria-hidden="true"></i>Trazabilidad</a>
            @if(! \App\Support\EstadoLoteCatalogo::loteEsCerrado($estado))
                @can('lotes.update')
                    <a class="dropdown-item" href="{{ route('lotes.edit', $lote) }}"><i class="ti ti-edit me-2" aria-hidden="true"></i>Editar</a>
                @endcan
            @endif
            @if(\App\Support\EstadoLoteCatalogo::loteSePuedeEliminar($estado))
                @can('lotes.delete')
                    <form method="POST" action="{{ route('lotes.destroy', $lote) }}" data-confirm-delete>
                        @csrf
                        @method('DELETE')
                        <button type="submit" class="dropdown-item text-danger"><i class="ti ti-trash me-2" aria-hidden="true"></i>Eliminar</button>
                    </form>
                @endcan
            @endif
        </div>
    </div>
</div>
