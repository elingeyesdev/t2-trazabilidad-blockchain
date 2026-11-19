# EDT 3.6 — Calendario de actividades agrícolas (#29)

Se conserva `GET /actividades/calendario`, su autenticación y permiso `action.permission:lotes,read`. La página Blade mantiene el menú lateral existente y carga el CSS Tabler verde ya compilado del proyecto, junto con FullCalendar **5.11.3**, que ya utilizaba esta pantalla. No se agregaron paquetes ni se modificaron contratos de Flutter.

La misma ruta devuelve JSON cuando recibe `Accept: application/json` y los parámetros `start` y `end` en formato `YYYY-MM-DD`. Son obligatorios para la consulta de eventos, con inicio anterior al fin e intervalo máximo de 62 días. **El fin es exclusivo**, conforme al intervalo visible de FullCalendar. La página inicial no recupera todas las actividades ni incrusta sus datos; cada navegación pide el periodo necesario.

## Fechas y responsable

Se mantiene la regla del formateador anterior: `fecha_planificada` tiene prioridad; si falta, se usa el día de `fechainicio`. La consulta aplica esa misma regla antes de recuperar registros. `fechafin` determina el estado completada, pero no cambia el día del evento. No se usa una fecha de creación ni se inventa una duración.

Los eventos son de día completo (`allDay: true`) y llevan `start: YYYY-MM-DD`, sin hora ni `end`. Las fechas planificadas son fechas civiles y nunca se convierten a UTC en JavaScript. Para el inicio se conserva la interpretación existente de Laravel en la zona configurada (`config('app.timezone')`, predeterminada `America/La_Paz`). El cliente envía las fechas civiles del intervalo de FullCalendar, sin `toISOString()` ni desplazamientos por la zona del navegador.

El esquema actual exige `fechainicio`, por lo que una actividad válida siempre tiene fecha. Como defensa ante datos antiguos de otro esquema, se excluyen las que carezcan de ambas fechas y se informa su cantidad autorizada en `sin_fecha`; nunca se colocan en hoy. No se cambió la nulabilidad del esquema para probar o permitir esos datos.

El responsable se obtiene de `actividad.usuario`, el trabajador asignado, y no del ejecutor del cierre. El esquema admite un solo asignado y exige su identificador; la representación utiliza `Sin asignar` si no puede resolverse un nombre. Los únicos estados del modelo son pendiente (`fechafin` nula) y completada (con fecha); ambos tienen texto visible y color semántico, sin inventar retrasos ni cancelaciones.

## Acceso y presentación

La consulta aplica `ActividadPermisos::aplicarScopeVisibles` y el ámbito de lotes antes del filtro de fechas, contadores o carga de relaciones. Se cargan lote, usuario y tipo anticipadamente. El JSON solo contiene identificador, descripción, día, URL de detalle, responsable, lote y estado. No hay caché compartida; la respuesta usa `private, no-store`.

Cada evento tiene un enlace generado por `route('actividades.show', ...)` al detalle EDT 3.5. Esa ruta revalida autorización y existencia al abrir; no hay un segundo modal con datos que puedan pertenecer a otra selección. Los errores 403/404 existentes se mantienen si cambia el acceso o se elimina la actividad.

La pantalla permite anterior, siguiente, hoy, mes y agendas de semana/día. En móvil comienza en agenda semanal para mantener los textos legibles. Los eventos muestran nombre, responsable, estado y lote; no dependen solo del color y sus enlaces pueden enfocarse con teclado. Los textos se insertan con nodos DOM y `textContent`, sin interpretar descripciones como HTML.

Se retiraron del calendario las acciones de creación y cierre y se deshabilitaron selección, arrastre y cambios de duración. Las demás pantallas conservan sus flujos. Hay mensajes de carga, ausencia y error con reintento; un fallo limpia los eventos anteriores para evitar presentarlos como actuales. Los cambios rápidos de periodo cancelan o descartan respuestas antiguas.

FullCalendar conserva sus recursos CDN existentes, por lo que requiere acceso a esa CDN. Si falla la carga, se informa y permanece el enlace al listado.

Referencias oficiales de la versión utilizada: [intervalos y fuentes JSON](https://legacy.fullcalendar.io/v5/events-json-feed), [renderizado de eventos](https://legacy.fullcalendar.io/v5/event-render-hooks).

## Verificación

Pruebas dirigidas: `php artisan test --compact --filter=CalendarioActividadesTest`, con SQLite aislado. Se comprueban fecha planificada distinta de inicio/cierre, fin exclusivo, fallback de inicio al final del día, navegación repetida entre periodos, responsables y estados, actividades ajenas excluidas, ámbito de otro jefe, autenticación, intervalos inválidos y página sin datos precargados. El detalle enlazado conserva el acceso a fotografía e insumos.

Las vistas se compilaron con `view:cache` y se limpió esa caché al terminar. No se modificaron los archivos fuente de los bundles Vite, por lo que no se requirió recompilación frontend. No se realizó verificación visual en navegador de escritorio/móvil. No hay migraciones, cambios de inventario ni modificaciones de archivos de Mobile.
