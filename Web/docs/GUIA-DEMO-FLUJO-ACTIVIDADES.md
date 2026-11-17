# Datos locales para probar el flujo EDT 3

Carga realizada el 16/11/2026. Son datos identificados con **DEMO EDT**, agregados a la base SQLite local, sin borrar los registros anteriores. Se aplicó la migración decimal pendiente y se guardó un respaldo previo en `storage/app/private/respaldos-demo/antes-demo-20261116-090420.sqlite`.

## Cuentas

Todas estas cuentas tienen contraseña `12345678` y están activas/aprobadas:

| Correo | Rol y uso |
|---|---|
| jefe.agricultor@agrofusion.local | Jefe principal: registrar lotes, asignar y supervisar actividades |
| operario.ana@agrofusion.local | Operaria del jefe principal: ejecutar sus actividades |
| operario.luis@agrofusion.local | Operario del jefe principal: ejecutar sus actividades |
| jefe.otroequipo@agrofusion.local | Jefe de otro equipo: comprobar separación de acceso |
| operario.otroequipo@agrofusion.local | Operario del otro equipo |

Los mismos correos y contraseñas sirven para la API/Flutter usando la dirección de tu servidor. No se cambió la contraseña de cuentas preexistentes durante la carga.

## Qué revisar

1. **Inicia como jefe principal.** En Lotes busca `DEMO EDT`. Debes ver los lotes 37, 38 y 39 de este equipo. El lote 40, `DEMO EDT - 04 Otro equipo`, corresponde al segundo jefe y no debe aparecer.
2. **Consulta el lote 37, `DEMO EDT - 01 Crecimiento`.** Sus actividades 202–205 están completadas con imágenes de prueba diferentes por actividad. La 204 muestra fertilización, resultado, ejecutor y consumo de **2.500 kg** del almacén agrícola. La siembra 203 consumió **25.000 kg** de semilla. El riego 205 tiene fotografía pero no consumo de almacén.
3. **Abre el calendario.** Hay fechas planificadas entre el 11 y el 19/11/2026; usa Hoy, Mes, Semana o Día. El jefe principal ve 11 actividades demo de su equipo, con responsables y estados. Selecciona cualquiera para abrir su detalle. Las actividades completadas conservan su fecha planificada aunque el cierre de demostración se haya registrado el 16/11.
4. **Inicia como Ana.** En el lote 37, completa primero la fertilización pendiente **206**, programada para el 16/11. Escribe un resultado y adjunta una imagen. El consumo planificado es **3.250 kg**; puedes confirmar esa cantidad. El fertilizante debe bajar de **97.500 a 94.250 kg**, con un solo consumo y movimiento. Su detalle debe mostrar resultado, foto, fecha y ejecutor.
5. **Inicia como Luis.** Después de cerrar la 206, completa el control de plagas **207** del mismo lote, programado para el 17/11, con **0.750 litros**. El stock debe bajar de **20.000 a 19.250 litros**. Antes de cerrar la 206, el sistema debe impedir saltarse el orden. La planificación futura no crea por sí sola una regla de prohibición de cierre por día; se respetan las reglas actuales de fase/secuencia.
6. **Vuelve a Ana.** Completa el riego **208** después de la 207: exige resultado y fotografía, sin consumo de almacén. El jefe supervisa estos cierres; no los realiza en nombre de los operarios.
7. **Prueba el inicio del flujo con Luis.** El lote 38, `DEMO EDT - 02 Preparación`, tiene preparación pendiente **209** y siembra **210**. Cierra primero la preparación. Después, la siembra permite registrar **20.000 kg** de semilla: de **475.000 a 455.000 kg**, si no realizaste otra siembra antes. La foto y el resultado deben quedar en esa actividad y el lote avanzar según las reglas existentes.
8. **Comprueba ausencia de datos.** La actividad **211** del lote 39 es un registro histórico de demostración: completada, sin fotografía y sin consumo. Debe indicarlo claramente. Su siembra **212** está pendiente y no debe mostrar planificación como consumo real.
9. **Comprueba permisos.** Ana no debe acceder al detalle privado de las actividades asignadas únicamente a Luis, ni ninguno de los dos al lote 40 del otro equipo. El jefe ajeno solo debe consultar su equipo. Cambiar el identificador en un enlace no debe dar acceso a una fotografía ajena.
10. **Consulta varias veces el detalle y cambia de fechas.** El stock y los consumos deben permanecer iguales. Para probar un reintento de cierre por API, repite resultado, bytes de foto y consumos del mismo cierre: debe devolver el cierre existente sin otro descuento. Cambiar esos datos sobre un cierre confirmado devuelve 409.

Para repetir la prueba de validación antes de cerrar, deja el resultado vacío, omite la fotografía o ingresa una cantidad superior al stock: el cierre debe rechazarse sin cambios. No hace falta consumir el stock para comprobar estos errores.

## Imagen para adjuntar

Se dejó una imagen válida en `storage/app/private/demo-flujo/foto-prueba-cierre.png`. Puedes seleccionarla desde el explorador al adjuntar evidencia, o usar tu propia fotografía. Las imágenes generadas dicen **DEMO EDT - IMAGEN DE PRUEBA**: son evidencias sintéticas para validar carga y consulta, no fotografías reales de cultivo.

## Reproducir la carga

Desde `Web`: `php artisan db:seed --class=DemoFlujoActividadesSeeder --force`.

El seeder solo admite SQLite local y utiliza el servicio real de cierre para descontar y registrar los consumos. Repetirlo no reinicia existencias, fechas, asignaciones, contraseñas o tareas existentes y no vuelve a cerrar una actividad completada. No es un comando de restauración de las pruebas realizadas manualmente. Los identificadores de esta guía corresponden a esta base local; en una base nueva se deben buscar los mismos nombres DEMO EDT.
