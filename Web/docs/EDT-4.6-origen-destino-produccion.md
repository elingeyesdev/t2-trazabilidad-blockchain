# EDT 4.6 — Origen y destino de la producción de planta

El recorrido corresponde a una instancia de `LoteProduccionPedido`. `ProcesoPlanta` es el catálogo de etapas; sus parámetros medidos y su cierre único se conservan. No se asignan consumos o productos a cada etapa ni se crean resultados parciales.

## Fuentes y persistencia

- **Consumo:** `LoteProduccionMateriaPrima.cantidad_usada`, con su partida concreta. El flujo existente guarda ahora el ID del movimiento de consumo y el lote de producción en dicho movimiento. La cantidad recibida procede exclusivamente de la línea de recepción identificada por `detallepedidoid` y `materiaprimaloteid`; se presenta por separado y nunca se suma como consumo.
- **Producto obtenido:** referencia directa al lote de producción de `InventarioPresentacionLote`. Se identifica la partida, el producto de catálogo y la presentación por sus claves, sin buscar coincidencias de nombres.
- **Ingreso y destino original:** el almacenaje nuevo conserva los IDs del producto, presentación y partida retornada por el servicio de inventario, además de los datos del ingreso: cantidades, unidad, nombres, almacén y fecha. Todo se registra en la misma transacción, con control del lote y del almacén. Una excepción revierte el ingreso completo.
- **Ubicación actual:** las partidas que conservan el ID del lote de producción muestran sus saldos y almacenes actuales. Un traslado o descuento posterior no reemplaza la cantidad ni el destino del ingreso original.

La migración agrega referencias nullable y `datos_ingreso`; no rellena registros anteriores. Es necesaria porque el almacenaje previo no relacionaba el producto concreto y su cantidad se modifica al descontar existencias. Los ingresos nuevos protegen sus referencias y datos originales frente a reemplazos mediante el modelo. La reversión de esta migración es manual para evitar eliminar evidencia registrada.

En registros antiguos se muestran las carencias expresamente: unidad histórica desconocida, producto sin vínculo directo o cantidad original no conservada. La unidad actual del catálogo se identifica como actual, sin atribuirla al consumo histórico. Una partida antigua vinculada acredita su relación con el proceso, pero su saldo actual no acredita la cantidad originalmente producida. No hay reconstrucciones por fecha, nombre o almacén ni conversiones con factores actuales en la consulta.

## Consulta web y API

`ProduccionPlantaRecorridoService` prepara un DTO autorizado que comparten el detalle web y la API. El detalle web reemplaza los resúmenes de materias y del primer almacén por colecciones completas, manteniendo Tabler y el estilo sobrio existente. Las tablas permiten desplazamiento horizontal dentro de su sección en móvil.

Rutas autenticadas, con `action.permission:lote_produccion,read`:

| Consulta | Respuesta |
| --- | --- |
| `GET /api/planta/lotes-produccion/{loteProduccion}` | Resource con el recorrido en `data` |
| `GET /api/planta/tareas/{asignacion}` | Contrato anterior más `origen_destino`; no se cambia el listado de tareas |
| `GET /api/planta/lotes-produccion/{loteProduccion}/tareas/{asignacion}` | Mismo detalle de tarea, comprobando también la pertenencia al lote de la URL |

Campos del recorrido:

| Campo | Contenido |
| --- | --- |
| `nivel` | `lote_produccion` |
| `lote_produccion` | ID, código y nombre del proceso concreto |
| `origenes[]` | Clave de consumo, insumo, partida, cantidades consumidas, unidades, movimiento, recepción y antecedentes autorizados |
| `productos_obtenidos[]` | Producto de catálogo, presentación y partida concreta; una sola entrada por partida |
| `ingresos_produccion[]` | Cada ingreso con su cantidad y destino original; los datos originales desconocidos permanecen en `null` |
| `ubicaciones_actuales[]` | Saldos y ubicaciones actuales de las partidas vinculadas |
| `restricciones` | Indicadores booleanos de información restringida, sin IDs ni conteos ocultos |

Las cantidades son cadenas decimales de seis posiciones o `null`; las colecciones sin datos son `[]`. No se calculan totales que mezclen unidades. La lista y cada relación se ordenan por claves estables; las etapas no multiplican consumos ni ingresos. Se cargan anticipadamente las relaciones utilizadas.

Los operarios consultan lotes con etapas propias; los jefes, lotes de su ámbito; el administrador consulta como supervisor. El inventario requiere además permiso y almacén visible. Los antecedentes agrícolas e industriales se autorizan por separado; no se devuelven proveedores, facturas, direcciones privadas, modelos completos ni rutas de archivos. Un proceso ajeno devuelve 404 en la API. Las tareas anidadas verifican ambos IDs. El listado web también restringe las materias relacionadas.

El GET web ya no completa fechas, reconstruye rutas ni promueve/cancela asignaciones. Esas operaciones continúan en los flujos de escritura existentes. La consulta no llama a sincronizaciones de inventario. Los datos y archivos congelados de los certificados no se modifican.

## Criterios comprobados

- [x] Identificación de materias y partidas vinculadas al lote de producción.
- [x] Cantidad realmente utilizada separada de la recibida, con unidad registrada o ausencia explícita.
- [x] Productos concretos relacionados por claves con el proceso que los generó.
- [x] Destinos registrados y ubicación actual diferenciados; varios ingresos y destinos se conservan.
- [x] Consulta equivalente desde web y API, manteniendo el contrato de tareas.
- [x] Permisos sobre el proceso y sus relaciones, datos ausentes y datos restringidos diferenciados; presentación móvil comprobada.

## Validación ejecutada

**46 pruebas pertinentes distintas aprobadas en PHP 8.2 / SQLite**, sin ejecutar la suite completa:

- `ProduccionPlantaRecorridoTest`: 20 casos sobre varios orígenes, origen compartido, consumo frente a recepción, productos/destinos múltiples, mismo catálogo en otro proceso, ubicación y saldos posteriores, seis decimales, registros antiguos y vacíos, ausencia de duplicación, invitado y usuarios ajenos, relaciones restringidas, IDs anidados, equivalencia web/API/tarea, GET repetidos sin escrituras SQL, conservación del certificado y archivo, almacenaje real, permisos del destino, reversión transaccional y eliminación de un lote nuevo sin procesar.
- `ApiPlantaTrabajoTest`: 18 casos de regresión del cierre único, parámetros, reintentos, recepción, permisos y consultas paginadas.
- `PantallasOperativasTest`: 7 casos de regresión de cantidades, estados, permisos y consulta web.
- `TrasladoPlantaMayoristaTest::test_traslado_descuenta_inventario_por_lote_presentacion`: descuento real por partida y conservación del vínculo del lote.

Edge comprobó el detalle a 1440 y 390 px: sin desbordamiento de la página ni excepciones JavaScript; tablas desplazables en móvil. Evidencia local en `storage/app/private/edt46-*`, ignorada por Git. La revisión utiliza una base aislada.

La migración local se aplicó después de crear un respaldo SQLite consistente. Se compararon los datos previos de consumos, almacenajes, certificados, inventario por partida y movimientos: permanecieron idénticos. No se realizó backfill. Pint revisó los archivos nuevos y `git diff --check` pasó.

No se ejecutaron PHP 8.3/8.4, PostgreSQL ni Flutter. No se cambiaron dependencias ni fuentes de assets; no se necesitó recompilar Vite. No se publicaron cambios en GitHub.
