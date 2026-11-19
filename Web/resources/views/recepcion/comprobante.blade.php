<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Comprobante de recepción</title>
<style>body{font-family:DejaVu Sans,sans-serif;color:#263442;font-size:11px}h1{font-size:19px;color:#166534}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:9px 5px;border-bottom:1px solid #dce1e6}th{background:#f4f6f8}.muted{color:#64748b}.firma{max-width:250px;max-height:110px;margin-top:15px}</style>
</head><body>
<h1>AgroFusion · Comprobante de recepción</h1>
<p>Recepción #{{ $numero }} · Envío {{ $datos['envio']['referencia'] }}</p>
<p>Fecha: {{ $datos['fecha'] }}<br>Recibido por: {{ $datos['firmante']['nombre'] }}</p>
@foreach($datos['destinos'] as $destino)<p>Destino: {{ $destino['nombre'] ?? '' }} {{ $destino['direccion'] ?? '' }}</p>@endforeach
<table><thead><tr><th>Pedido / Producto</th><th>Presentación</th><th>Enviado</th><th>Recibido</th></tr></thead><tbody>
@foreach($datos['lineas'] as $linea)<tr><td>{{ $linea['pedido'] }}<br>{{ $linea['producto'] }}@if($linea['motivo'])<br><span class="muted">{{ $linea['motivo'] }}</span>@endif</td><td>{{ $linea['presentacion'] }}</td><td>{{ $linea['cantidad_enviada'] }} {{ $linea['unidad'] }}</td><td>{{ $linea['cantidad_recibida'] }} {{ $linea['unidad'] }}</td></tr>@endforeach
</tbody></table>
<img src="{{ $firma }}" class="firma" alt="Firma manuscrita del receptor"><p class="muted">Firma manuscrita registrada con la cuenta autenticada del destinatario.</p>
</body></html>
