<!doctype html><html lang="es"><head><meta charset="utf-8"><title>{{ $datos['emision']['codigo'] }}</title>
<style>body{font-family:DejaVu Sans,sans-serif;font-size:10px;color:#1e293b}h1{font-size:18px;color:#166534}h2{font-size:14px}h3{font-size:12px;margin-top:18px}table{width:100%;border-collapse:collapse}th,td{border-bottom:1px solid #dbe3dc;padding:6px;text-align:left;vertical-align:top}dt{font-weight:bold}dd{margin:0 0 6px}tr{page-break-inside:avoid}.text-muted{color:#64748b}.small{font-size:9px}</style>
</head><body><h1>AgroFusion · Certificación {{ $datos['ambito'] === 'campo' ? 'de campo' : 'de planta' }}</h1>
@include('certificados.partials.instantanea', ['datos' => $datos])
<p style="margin-top:20px;color:#64748b">Documento de la emisión indicada. Conserva los datos registrados al emitir.</p>
</body></html>
