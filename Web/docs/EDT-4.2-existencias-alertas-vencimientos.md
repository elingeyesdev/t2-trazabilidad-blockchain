# EDT 4.2: existencias, alertas y vencimientos por almacén

## Modelo y reglas

El saldo físico continúa en `insumo.stock`, asociado a su almacén. Las partidas de materia prima y de presentación desglosan ese saldo; no se suman nuevamente al total. El saldo histórico sin partida permanece identificado como «sin fecha registrada». No se inventan fechas, proveedores, vínculos ni movimientos históricos.

El mínimo pertenece al insumo del almacén: `null` significa sin configurar y cero es un mínimo válido. La alerta compara la disponibilidad con el mínimo usando `<=`. Se muestran por separado saldo físico, reservas, cantidades vencidas o bloqueadas y disponibilidad. Las reservas comerciales conservan su origen en pedidos confirmados.

Una partida está próxima a vencer durante los siete días anteriores. Puede consumirse durante todo el día de vencimiento, con calendario `America/La_Paz`; al día siguiente queda bloqueada. Las partidas sin fecha siguen permitidas, con etiqueta explícita. La falta de conformidad también impide consumir. El retiro de vencidos se registra mediante el movimiento autorizado correspondiente.

Las cantidades de inventario se calculan con seis decimales, sin acumulación binaria de flotantes. El cierre de actividades mantiene su contrato de tres decimales. Las equivalencias de partidas existentes usan sus cantidades físicas registradas, sin reinterpretarlas con factores actuales del catálogo. El orden FIFO existente se conserva.

La producción agrícola almacenada conserva su circuito propio en `produccionalmacenamiento` y su consulta existente. El registro de cosecha de EDT 4.1 no genera por sí solo un ingreso de insumos: no se equipara una semilla con el producto cosechado ni se reconstruyen existencias desde cosechas históricas.

## Operaciones y auditoría

`InventarioExistenciaService` centraliza disponibilidad, selección de partidas, reservas y descuentos. `InventarioMovimientoService` comparte validaciones entre web y API. Los cambios se ejecutan en transacciones, verificando permisos y pertenencia al almacén.

Un ajuste requiere motivo y deja usuario autenticado, unidad histórica, cantidad, partida y saldo anterior/posterior. Las pantallas antiguas de edición conservan el ingreso de un conteo final; el servicio calcula y audita su diferencia. El mínimo se configura independientemente. El cliente no puede imponer el actor ni los saldos auditados.

Cuando existen partidas se exige identificar el origen: `m:ID` para materia prima, `p:ID` para presentación y `0` para saldo histórico sin partida. Se rechazan partidas ajenas, cantidades insuficientes, stock reservado y consumos vencidos. La reversión de procesamiento devuelve a la misma partida y conserva su vencimiento. El cierre conserva su protección contra reintentos duplicados.

En SQLite el descuento inicia con una escritura antes de leer el saldo para evitar promociones de bloqueo de transacciones diferidas. En PostgreSQL se bloquean almacenes e insumos en orden estable. Las consultas no generan partidas ni reconstruyen inventarios automáticamente.

## Interfaz y compatibilidad

Las nuevas consultas anidadas de almacén ofrecen existencias, configuración de mínimos y movimientos con detalle, filtros y paginación. Las vistas mantienen Tabler, la paleta verde y navegación existente. Presentan validaciones y conservan los datos del formulario al fallar.

Los nuevos recursos exponen cantidades decimales como cadenas. La API anterior de movimientos conserva su campo numérico `cantidad` y añade `cantidad_decimal` para clientes que necesitan precisión. Se conservan los códigos de autorización de las rutas antiguas; las consultas anidadas no revelan almacenes ajenos. No se agregan paquetes ni canales de notificación.

## Migración y validación local

La migración agrega vínculos y campos auditables opcionales, precisión y vencimiento de presentaciones. Verifica rangos y permite reaplicación sin duplicar estructura. Su reversión no elimina información histórica.

Antes de aplicarla a la base local se guardó el respaldo privado `storage/app/private/respaldos-demo/antes-edt42-20261117-225745.sqlite`. Se compararon y preservaron los datos preexistentes de 60 insumos, 61 movimientos, 19 producciones y 7 líneas de consumo de planta; las tablas de partidas estaban vacías.

Las pruebas funcionales cubren mínimos nulos/cero, aislamiento por almacén, permisos, precisión, fechas límite, reservas, auditoría, reversión, cierre e idempotencia. La prueba de concurrencia utiliza dos procesos PHP independientes contra un archivo SQLite y comprueba que dos salidas incompatibles no confirmen ambas.

Se ejecutó la suite completa: 460 pruebas pasaron, una quedó omitida por su condición de base real y cuatro detectaron diferencias de autorización o tiempo de arranque. Tras corregir esos casos, la regresión sobre sus clases y los flujos afectados terminó con **43 pruebas aprobadas y 494 aserciones**, incluida concurrencia real. El registro local está en `storage/logs/edt42-verificacion-final.log`. No se repitió toda la suite después de esas correcciones.

La compilación Vite y la compilación de vistas se verificaron. Se revisó la pantalla de existencias en navegador a 1440 y 390 píxeles, sin desbordamiento de página ni errores JavaScript, incluyendo rechazo de mínimo negativo y guardado válido. La revisión usa una copia de la base, no credenciales de usuarios reales.

PostgreSQL y la matriz remota PHP/Flutter no se ejecutaron en este entorno. Los cambios permanecen locales hasta recibir la orden de publicación.
