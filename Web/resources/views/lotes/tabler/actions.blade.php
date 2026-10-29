<div class="d-flex flex-wrap gap-2 align-items-center mt-4 pt-3 border-top">
    <a href="{{ route('lotes.index') }}" class="btn"><i class="ti ti-arrow-left me-2" aria-hidden="true"></i>Volver a lotes</a>
    @if(empty($ocultarGestion))
        @can('lotes.update')<a href="{{ route('lotes.edit', $lote) }}" class="btn ms-sm-auto"><i class="ti ti-edit me-2" aria-hidden="true"></i>Editar lote</a>@endcan
        @can('lotes.delete')
            @if(\App\Support\EstadoLoteCatalogo::loteSePuedeEliminar($lote->estadoTipo->nombre ?? null))
                <form method="POST" action="{{ route('lotes.destroy', $lote) }}" data-confirm-delete>@csrf @method('DELETE')<button type="submit" class="btn btn-outline-danger">Eliminar lote</button></form>
            @endif
        @endcan
    @endif
</div>
