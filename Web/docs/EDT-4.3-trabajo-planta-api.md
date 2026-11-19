# EDT 4.3: trabajo de planta desde la API

## Diagnóstico y decisiones

Laravel 12 y Sanctum ya autentican la API; la matriz de permisos es la misma que usa la web. Las tareas reales son `asignacion_etapa_planta`, vinculadas a `lote_produccion_pedido`, proceso, máquina, operario y, cuando existe, al paso de la ruta. No hay asignaciones por turno o grupo ni propiedad de planta en el catálogo de máquinas: la autorización de uso nace de la máquina explícitamente asignada a la tarea. No se agregan reservas ni ocupación exclusiva.

La secuencia se obtiene del servicio de transformación y del `orden` configurado en la ruta/asignación, no de los identificadores ni de los nombres. Se conservan los procesos y compatibilidades existentes. Una máquina inactiva se considera en mantenimiento.

La recepción agrícola usa `pedido`, sus `detallepedido` y `envio_asignacion_multiple`. La aceptación del pedido ya descuenta el origen; recibir solo acredita el destino. Una cosecha (`produccion`), su almacenamiento agrícola (`produccionalmacenamiento`), una partida de inventario (`materia_prima_lote`) y el lote industrial (`lote_produccion_pedido`) son entidades distintas.

Por decisión del usuario se conserva **un cierre por etapa con parámetros configurados**, sin resultados parciales ni campos nuevos de entrada/salida. Las cantidades se registran como mediciones cuando la etapa tenga esa variable configurada, con su unidad y rango. Las etapas no descuentan nuevamente las materias primas consumidas al crear el lote industrial. La recepción también mantiene un pesaje final por envío: aceptar menos que lo enviado registra una discrepancia y cierra la recepción; no deja un saldo para una segunda recepción parcial.

## Servicios y persistencia

- `AsignacionEtapaPlantaService`: autorización del operario, orden, relación con la ruta, recepción previa cuando el pedido tiene envío, proceso activo y máquina asignada, compatible y disponible. Cierre, registro y promoción de la siguiente tarea se guardan en una transacción.
- `LoteProduccionParametrosService`: rechaza variables ajenas, repetidas, faltantes y mediciones fuera del rango. Conserva `valor` para las vistas existentes y agrega `valor_decimal` al resultado para evitar perder precisión al presentarlo.
- `RecepcionPlantaEnvioService`: compartido por web y API. Valida destino inequívoco y permisos, envío en transporte, líneas exactas del pedido, pesajes positivos de hasta seis decimales y límite enviado por línea. No cambia el almacén de un insumo ajeno ni busca productos por semejanza de nombre.
- La nueva recepción crea una partida por línea en el destino y un movimiento auditado, actualizando una sola vez `insumo.stock`. La unidad del pesaje es kg, según el contrato web existente. Conserva el vencimiento de la partida despachada cuando hay un vínculo verificable; aplica la disponibilidad y las fechas de EDT 4.2. Un origen con partidas, pero sin identificación de la efectivamente despachada, se rechaza en lugar de adivinarlo. El saldo de origen en tránsito no se vuelve a consumir ni se exige que siga disponible después de su salida.
- Cuando el detalle referencia almacenamiento de una cosecha, el comprobante conserva almacenamiento, producción y lote agrícola. Un origen histórico sin esos vínculos mantiene sus identificadores nulos; no se inventan asociaciones.

La migración `2026_11_18_110000_trazabilidad_recepcion_planta.php` agrega `recepcion_planta_datos` opcional al envío y `detallepedidoid` opcional con FK restrictiva a la partida recibida. El comprobante conserva cantidades, unidad, actor/fecha del envío y vínculos reales a partida y movimiento. No rellena recepciones históricas ni borra datos al revertirse.

Se aplicó localmente con respaldo privado `storage/app/private/respaldos-demo/antes-edt43-20261118-184818.sqlite` y se verificó que los registros preexistentes de envíos y partidas conservaran sus valores.

## Contrato móvil

Todas las rutas siguientes empiezan en `/api/planta`, requieren Sanctum (`Authorization: Bearer …`) y devuelven JSON incluso si falta `Accept`. Los recursos individuales se devuelven bajo `data`; los listados incluyen `data`, `links` y `meta`.

| Método y ruta | Permiso y alcance |
| --- | --- |
| `GET /tareas` | `lote_produccion.view`; exclusivamente operario planta y sus propias asignaciones |
| `GET /tareas/{asignacion}` | Mismo permiso y titularidad |
| `POST /lotes-produccion/{loteProduccion}/tareas/{asignacion}/completar` | Mismo permiso, titularidad y relación padre/hijo |
| `GET /recepciones` | `recepcion_planta.view`; destino de su planta, o supervisión autorizada |
| `GET /recepciones/{pedido}` | Mismo permiso y destino autorizado |
| `POST /recepciones/{pedido}/confirmar` | `recepcion_planta.confirm`; jefe autorizado del almacén destino |

Tareas admite `estado` (`pendiente`, `programada`, `completada`, `cancelada`), `page` y `per_page` (1–50). No acepta un usuario arbitrario para ampliar el listado. Incluye proceso, máquina, estado, fechas, lote industrial y resultado persistido. El detalle añade `meta.puede_completar`, `requisito_pendiente`, `maquinas_elegibles`, `parametros_requeridos` y `permite_parciales: false`. La única máquina elegible es la asignada. El servidor vuelve a comprobar todo al ejecutar.

Ejemplo de cierre, usando los identificadores publicados por el detalle:

```json
{"parametros":[{"variableestandarid":12,"valor":"95.123456"}]}
```

Una etapa sin mediciones configuradas recibe `{"parametros":[]}`. El cliente no envía responsable, máquina, proceso, fechas administrativas ni estado. El registro toma el operario autenticado y la hora del servidor. Las mediciones tienen su unidad configurada, que no tiene por qué ser kg.

Recepciones admite `recibido=0|1` (pendientes por defecto), `page` y `per_page`. Incluye líneas enviadas en kg y el comprobante `recepcion` cuando existe. Para confirmar se usa un mapa por **detallepedidoid**, no por producto ni por lote industrial:

```json
{"cantidades":{"41":"90.123456","42":"9.000001"}}
```

Se requiere exactamente una cantidad por cada línea. Se recomiendan cadenas decimales con punto y sin exponentes para el pesaje. La presentación y unidad de las cantidades de cosecha no se reinterpretan usando un catálogo nuevo; el límite de recepción es el kg enviado ya registrado en el pedido, como en la web existente.

Respuestas: `200` confirma o devuelve un reintento idéntico; `401` sin sesión; `403` sin rol/permiso operativo; `404` para tarea, relación o destino ajeno; `422` con `message` y `errors` por campos para validaciones; `409` para un pesaje/resultado incompatible con una operación ya confirmada. Los errores internos de escritura se reportan en el servidor y devuelven un mensaje genérico.

## Integridad y compatibilidad web

El envío se protege dentro de la transacción sobre el pedido y almacén; el cierre de etapas protege primero el lote industrial y luego la asignación y máquina. SQLite adquiere escritura antes de leer; otros motores usan `FOR UPDATE`. El inventario reutiliza los bloqueos y decimales de EDT 4.2. Un fallo revierte partidas, movimientos, saldos y estados relacionados.

El pesaje confirmado guarda una huella canónica de las cantidades por línea. El cierre único guarda una huella de parámetros ordenados y valores decimales normalizados en el JSON del registro existente. Un reintento no crea nuevos efectos y no depende de fechas enviadas por el cliente. Un registro histórico sin huella verificable no se interpreta como un reintento idéntico.

Las pantallas existentes de tareas, procesamiento e inventario leen los mismos registros. El pedido muestra un comprobante por línea con cantidad exacta y partida destino. La tarea permite ingresar mediciones reales mediante el componente de formulario existente; los parámetros de la línea y sus rangos siguen definidos por el jefe. La línea de procesamiento presenta el valor decimal guardado. Se conserva Tabler y la identidad visual.

## Verificación

Se agregaron pruebas de autenticación real con token, permisos, titularidad, rutas anidadas, orden, recepción requerida, máquina inactiva/incompatible, campos protegidos, parámetros y cantidades inválidos, fechas/actor del servidor, idempotencia y conflictos, reversión ante fallo, varios lotes agrícolas, precisión, vencimiento, coherencia web/API y ausencia de consultas por fila en los listados.

`ApiPlantaTrabajoTest` y `PlantaConcurrenciaTest`: **19 pruebas aprobadas, 173 aserciones**. La concurrencia usa dos procesos PHP y una base SQLite aislada: pesajes incompatibles generan un solo ingreso; resultados incompatibles generan un solo cierre. No se presenta una secuencia de llamadas como concurrencia.

Las regresiones pertinentes incluyen cosechas EDT 4.1, existencias EDT 4.2, recepción/pesaje, aislamiento de planta y firmas/cierre logístico. Sus clases existentes pasaron en las ejecuciones focalizadas. No se ejecutó toda la suite del repositorio ni Flutter porque no se modificó su código. PostgreSQL y la matriz remota PHP 8.2/8.3/8.4 no se ejecutaron localmente.

Se compilaron las vistas Blade y se verificó el formato de los archivos PHP nuevos y servicios modificados. Se revisaron en Edge las pantallas reales de recepción y tarea completada usando una copia SQLite de prueba, con caché y cuentas aisladas: escritorio de 1440 px y recepción móvil de 390 px, sin desbordamiento de página ni excepciones JavaScript. Las tablas conservan su desplazamiento horizontal interno. No fue necesario recompilar Vite porque no se modificaron sus entradas de assets.
