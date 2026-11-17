@extends('layouts.app')
@section('title', 'Calendario de actividades | AgroFusion')
@section('page_title', 'Calendario de actividades')
@push('styles')
@vite(['resources/css/tabler-lotes.css'])
<link href="https://cdn.jsdelivr.net/npm/fullcalendar@5.11.3/main.min.css" rel="stylesheet">
<style>
.calendario-actividades { --fc-button-bg-color: #23754b; --fc-button-border-color: #23754b; --fc-button-hover-bg-color: #195c39; --fc-button-hover-border-color: #195c39; --fc-button-active-bg-color: #195c39; --fc-button-active-border-color: #195c39; }
.calendario-actividades .fc-toolbar { flex-wrap: wrap; gap: .75rem; }
.calendario-actividades .fc-toolbar-title { font-size: 1.3rem; text-transform: capitalize; }
.calendario-actividades .fc-event { white-space: normal; cursor: pointer; padding: .25rem; border-radius: .3rem; }
.calendario-actividades .fc-event-main { color: inherit; }
.calendario-actividades .actividad-pendiente { background: #fff4d6; border-color: #b87500; color: #684300; }
.calendario-actividades .actividad-completada { background: #edf5f0; border-color: #23754b; color: #195c39; }
.calendario-actividades .fc-event:focus-visible { outline: 3px solid #23754b; outline-offset: 2px; }
.calendario-actividades .evento-linea { display: block; overflow-wrap: anywhere; }
.calendario-actividades .evento-nombre { font-weight: 600; }
.calendario-actividades .evento-meta { font-size: .8rem; }
.calendario-actividades .fc-list-event:hover td { background: #edf5f0; }
@media (max-width: 575px) {
 .calendario-actividades .card-body { padding: .75rem; }
 .calendario-actividades .fc-toolbar-chunk { width: 100%; text-align: center; }
 .calendario-actividades .fc-toolbar-title { font-size: 1.1rem; }
 .calendario-actividades .fc-button { padding: .4rem .55rem; }
}
</style>
@endpush
@section('content')
<div class="calendario-actividades">
 <div class="card">
  <div class="card-header d-flex justify-content-between align-items-center flex-wrap" style="gap:.75rem;">
   <h2 class="card-title mb-0">Calendario de actividades</h2>
   <a href="{{ route('actividades.index') }}" class="btn btn-outline-primary btn-sm">Ver listado</a>
  </div>
  <div class="card-body">
   <p class="text-muted small">Actividades por fecha planificada y trabajador asignado. Si no hay fecha planificada, se utiliza la de inicio. Selecciona una actividad para consultar su detalle, fotografía e insumos.</p>
   <div class="d-flex flex-wrap mb-3" style="gap:.5rem;" aria-label="Leyenda de estados">
    <span class="badge bg-warning-lt">Pendiente</span><span class="badge bg-success-lt">Completada</span>
   </div>
   <p id="calendarioEstado" role="status" aria-live="polite">Cargando actividades…</p>
   <div id="calendarioError" class="alert alert-danger" role="alert" hidden>
    <span id="calendarioErrorTexto"></span>
    <button type="button" class="btn btn-outline-danger btn-sm ml-2" id="calendarioReintentar">Volver a intentar</button>
   </div>
   <p id="calendarioSinFecha" class="text-muted small" hidden></p>
   <div id="calendar" aria-label="Calendario de actividades agrícolas"></div>
   <noscript>Activa JavaScript para consultar el calendario o utiliza el listado de actividades.</noscript>
  </div>
 </div>
</div>
@endsection
@push('scripts')
<script src="https://cdn.jsdelivr.net/npm/fullcalendar@5.11.3/main.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/fullcalendar@5.11.3/locales/es.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function () {
 const estado = document.getElementById('calendarioEstado');
 const error = document.getElementById('calendarioError');
 const errorTexto = document.getElementById('calendarioErrorTexto');
 const sinFecha = document.getElementById('calendarioSinFecha');
 const reintentar = document.getElementById('calendarioReintentar');
 if (!window.FullCalendar) {
  estado.textContent = 'No se pudo cargar el calendario. Puedes consultar el listado de actividades.';
  return;
 }
 let peticion = 0;
 let controlador;
 const calendario = new FullCalendar.Calendar(document.getElementById('calendar'), {
  locale: 'es', firstDay: 1, timeZone: 'local', height: 'auto', fixedWeekCount: false,
  initialView: window.matchMedia('(max-width: 575px)').matches ? 'listWeek' : 'dayGridMonth',
  headerToolbar: { left: 'prev,next today', center: 'title', right: 'dayGridMonth,listWeek,listDay' },
  buttonText: { today: 'Hoy', month: 'Mes', week: 'Semana', day: 'Día' },
  buttonHints: { prev: 'Periodo anterior', next: 'Periodo siguiente', today: 'Ir a hoy' },
  views: { listWeek: { buttonText: 'Semana' }, listDay: { buttonText: 'Día' } },
  noEventsText: 'No hay actividades en este periodo', dayMaxEvents: 3,
  editable: false, selectable: false, eventStartEditable: false, eventDurationEditable: false,
  displayEventTime: false,
  events: function (info, exito, fallo) {
   const numero = ++peticion;
   controlador?.abort();
   controlador = new AbortController();
   error.hidden = true;
   sinFecha.hidden = true;
   estado.textContent = 'Cargando actividades…';
   const url = new URL(@json(route('actividades.calendario')), window.location.origin);
   // FullCalendar's range end is exclusive. Keep civil dates, without UTC conversion.
   url.searchParams.set('start', info.startStr.split('T')[0]);
   url.searchParams.set('end', info.endStr.split('T')[0]);
   fetch(url, { credentials: 'same-origin', headers: { Accept: 'application/json' }, cache: 'no-store', signal: controlador.signal })
    .then(function (respuesta) {
     if (!respuesta.ok || respuesta.redirected) throw new Error('No se pudieron consultar las actividades. Comprueba tu sesión y vuelve a intentar.');
     return respuesta.json();
    }).then(function (datos) {
     if (numero !== peticion) { fallo(new Error('Petición sustituida')); return; }
     if (!Array.isArray(datos.eventos)) throw new Error('La respuesta del calendario no es válida.');
     exito(datos.eventos);
     estado.textContent = datos.eventos.length ? datos.eventos.length + ' actividades en el periodo visible.' : 'No hay actividades en este periodo';
     sinFecha.hidden = !datos.sin_fecha;
     sinFecha.textContent = datos.sin_fecha + ' actividades sin fecha: no se ubican en el calendario. Puedes consultarlas en el listado.';
    }).catch(function (problema) {
     if (numero !== peticion || problema.name === 'AbortError') { fallo(problema); return; }
     exito([]);
     estado.textContent = '';
     errorTexto.textContent = problema.message;
     error.hidden = false;
    });
  },
  eventContent: function (info) {
   const bloque = document.createElement('div');
   const datos = info.event.extendedProps;
   [[info.event.title, 'evento-nombre'], [datos.responsable, 'evento-meta'], [datos.estado, 'evento-meta'], [datos.lote, 'evento-meta']].forEach(function (fila) {
    if (!fila[0]) return;
    const linea = document.createElement('span');
    linea.className = 'evento-linea ' + fila[1];
    linea.textContent = fila[0];
    bloque.appendChild(linea);
   });
   return { domNodes: [bloque] };
  },
  eventDidMount: function (info) {
   info.el.setAttribute('aria-label', [info.event.title, info.event.extendedProps.responsable, info.event.extendedProps.estado, 'Abrir detalle'].join('. '));
  }
 });
 reintentar.addEventListener('click', function () { calendario.refetchEvents(); });
 calendario.render();
});
</script>
@endpush
