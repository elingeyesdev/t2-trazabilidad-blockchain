@if($cert->esCertificado() && filled($cert->blockchain_estado))
<div class="card mt-3"><div class="card-header">Estado actual de integración</div><div class="card-body">
<p class="text-muted small">El estado técnico puede actualizarse; los datos y el documento emitidos se conservan.</p>
<dl><dt>Estado</dt><dd>{{ $cert->blockchain_estado }}</dd>
@if($cert->blockchain_hash)<dt>Hash del registro</dt><dd style="overflow-wrap:anywhere">{{ $cert->blockchain_hash }}</dd>@endif
@if($cert->blockchain_txid)<dt>Transacción</dt><dd style="overflow-wrap:anywhere">{{ $cert->blockchain_txid }}</dd>@endif
@if($cert->blockchain_solicitud_id)<dt>Solicitud</dt><dd>{{ $cert->blockchain_solicitud_id }}</dd>@endif
</dl>
@can('certificaciones.update')
@if(in_array($cert->blockchain_estado, ['pendiente', 'error'], true))
<form method="POST" action="{{ route('certificaciones.blockchain.sincronizar', $cert) }}">@csrf<button class="btn btn-outline-success" type="submit">Actualizar estado de integración</button></form>
@endif
@endcan
</div></div>
@endif
