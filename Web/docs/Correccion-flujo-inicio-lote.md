# Corrección del inicio de lote y actividades web

El encargado del lote y el ejecutor de una tarea son referencias distintas. En el alta web el jefe conserva el lote y debe seleccionar un agricultor activo y aprobado de su equipo, además de declarar si el terreno requiere preparación.

- **Requiere preparación:** se crea una única preparación asignada al agricultor. Su cierre con resultado y foto habilita y asigna la siembra al trabajador de esa preparación, incluida una reasignación posterior.
- **Ya preparado:** se conserva la declaración y se asigna directamente la siembra; no se inventa una actividad de preparación realizada.
- El identificador del formulario permite recuperar el mismo lote al reintentar. Reutilizarlo con datos distintos produce un conflicto. El lote, historial inicial y primera tarea se guardan en una transacción.
- El catálogo de tipos y el cierre validan la fase actual. Los botones de Trazabilidad y la cola comparten esa validación.

## Accesos y permisos

El administrador ve **Vehículos** si tiene `vehiculos.view`, usando `envios.vehiculos`. El listado conserva su botón de creación condicionado a `vehiculos.create`; no se amplían permisos.

El jefe dispone de **Nueva actividad** en Actividades y **Reasignar** en tabla, tarjetas, detalle y Trazabilidad. Solo se editan tareas pendientes del propio equipo, conservando lote y tipo. Se registra el historial de responsables en el detalle de la actividad. Las tareas cerradas no se modifican.

## Preparación incompatible en lotes existentes

En una preparación pendiente posterior a una siembra realizada, el jefe del equipo puede usar **Cancelar preparación incompatible**, indicando un motivo obligatorio. Se conservan fecha, autor y motivo; la tarea no se borra ni se marca como ejecutada. La cancelación la retira de la cola, notificaciones y recuentos de pendientes. Se presenta como cancelada en listado, detalle, historial, calendario y API.

No se cancelan automáticamente registros antiguos. Una preparación con consumos aplicados requiere revisión y no se cancela mediante esta acción.

Caso de referencia leído sin modificar: **Fresa - Parcela 01**, lote 41; siembra 214 completada, preparación 215 pendiente y riego 216 detrás. La prueba aislada reproduce ese orden y compara siembra, evidencia, consumo y saldo antes y después de cancelar la preparación y cerrar el riego.

Para continuar en la instalación local: ingresar como jefe del lote, abrir `/lotes/41/trazabilidad`, localizar la preparación pendiente, indicar el motivo y cancelar. Luego ingresar como agricultor asignado y cerrar el riego en turno.

## Aplicación y comprobación

Migración aditiva: `2026_11_26_100000_ordenar_inicio_lote_y_cancelacion_actividades.php`. Sus campos nuevos son nulos para los registros históricos. Se aplicó localmente con `APP_ENV=review`, con respaldo SQLite consistente previo en `storage/app/private/flujo-web-antes-20261126-134311-d7b303.sqlite`. No se ejecutaron seeders ni correcciones de datos operativos.

Se verificaron peticiones web autenticadas y vistas Blade en SQLite de pruebas: creación en ambos recorridos, cierres con fotografía, consumos, reintentos, reasignación, cancelación histórica, restricciones de equipo y permisos de vehículos. La regresión seleccionada incluye cierre API, alta/asignaciones API y secuencia.

- Regresión principal: **43 pruebas, 553 aserciones, aprobadas** (`storage/logs/flujo-web-final.log`).
- Flujo y calendario: **13 pruebas, 207 aserciones, aprobadas** (`storage/logs/flujo-web-calendario.log`); nueve pertenecen también al conjunto anterior.
- Comprobación final del caso existente, incluida protección frente a edición y eliminación por API: **1 prueba, 40 aserciones, aprobada** (`storage/logs/flujo-web-fresa.log`).
- En total, los conjuntos cubren **47 pruebas distintas**.

La comprobación HTTP local real del administrador incluyó login con CSRF, enlace de menú, listado, botón Nuevo y formulario de vehículo (200). Las huellas de actividades y consumos originales de Fresa permanecieron iguales tras aplicar la migración.

La revisión visual y la ejecución de JavaScript en un navegador no se completaron: el host de automatización del navegador no estuvo disponible. Tampoco se ejecutó la suite completa, PHP 8.3/8.4 ni CI remoto. No se subieron cambios.
