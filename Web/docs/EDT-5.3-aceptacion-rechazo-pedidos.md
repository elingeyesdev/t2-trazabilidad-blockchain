# EDT 5.3 · Aceptación y rechazo de pedidos

## Reglas verificadas en el repositorio

| Flujo | Usuario y ámbito efectivo | Estados de entrada | Aceptación | Rechazo |
|---|---|---|---|---|
| Agrícola | Jefe agricultor operativo con `pedidos.update`, acceso al pedido y gestión de **todos** sus almacenes de origen | `sin asignacion`, `pendiente`, con envío programado sin salida, firmas ni recepción | Comprueba partidas, vencimientos, conversiones históricas y saldo acumulado; **descuenta físicamente** el origen; confirma el pedido y habilita el transporte programado | Exige motivo; cambia a rechazado y cancela únicamente la programación pendiente. No acredita stock |
| Distribución | Mayorista/jefe mayorista operativo con `pedidos_distribucion.update`, pedido dirigido a su almacén y líneas de su ámbito | `pendiente`, sin transporte, despacho ni recepción | Conserva EDT 5.1: comprueba disponibilidad y confirma; **reserva por el estado confirmado**, sin salida física. Conserva el circuito legado de coordinación con planta cuando corresponda | Exige motivo y cambia a rechazado. No modifica stock físico ni reservas ajenas |

Decisión confirmada con el usuario: **no habilitar rechazo de pedidos confirmados**. En estos flujos los pendientes no mantienen una reserva activa: no se inventa una liberación ni un aumento de cantidades. La aceptación agrícola ya descuenta y no se revierte mediante rechazo. La distribución descuenta físicamente al despachar, como antes.

Ser administrador, creador, destinatario o transportista no concede por sí solo la facultad de decidir. Las acciones anunciadas y los formularios aplican las mismas comprobaciones que el servicio; este vuelve a validarlas dentro de la transacción.

La reapertura de distribución ya existente se conserva; no se incorporó otra transición. La decisión anterior permanece como historial y una decisión posterior obtiene otra secuencia.

## Persistencia e integridad

No existía un historial estructurado de decisiones: el motivo era opcional y se concatenaba a observaciones. La migración `2026_11_19_140000_create_pedido_decision.php` agrega una tabla con pedido, acción, estado anterior/resultante, motivo, actor, fecha y secuencia. Las relaciones, claves foráneas y secuencias únicas conservan la vinculación. No se reinterpretan observaciones ni se inventan responsables o motivos históricos. La consulta usa esta única fuente para la nueva decisión.

Pedido, decisión, programación y cantidades se escriben en la misma transacción, con reintento de bloqueos. Se bloquea el pedido antes de comprobar su estado y la programación agrícola antes de modificarla. Las reservas reutilizan los bloqueos existentes de almacenes/productos, ordenados por identificador. SQLite adquiere escritura antes de leer dentro de la transacción. Los acumulados de distribución sin presentación también se verifican con decimales y el saldo/reservas del servicio de existencias, incluyendo reservas en otras presentaciones.

Un fallo al guardar el historial revierte stock, estado y programación. La aceptación no crea firmas, no consume QR ni registra entregas. Un despacho o recepción incompatible impide una decisión nueva; un reintento equivalente solo devuelve el resultado persistido.

## Contrato web y API

Se reutilizan `POST /api/pedidos-agricolas/{id}/transiciones` y `POST /api/pedidos-distribucion/{id}/transiciones`, así como las rutas web de decisión existentes. `accion` admite las acciones del contrato anterior. Para rechazar, `motivo_rechazo` es texto obligatorio, recortado y de hasta 500 caracteres. El cliente no determina actor, fecha, decisión, estado ni reservas.

Las consultas y respuestas de transición incorporan de forma aditiva:

```json
{
  "estado": "rechazado",
  "motivo_rechazo": "No es posible atender la fecha.",
  "decision": {
    "accion": "rechazar",
    "estado_resultante": "rechazado",
    "motivo": "No es posible atender la fecha.",
    "usuarioid": 12,
    "fecha": "2026-11-19T14:00:00.000000Z"
  },
  "acciones_disponibles": []
}
```

`acciones_disponibles` informa las decisiones `aceptar`/`rechazar`, no las operaciones logísticas. Es orientativo y se recalcula al ejecutar. Se mantiene la forma plana de la API agrícola legada y su protección contra actualización libre de estado; las rutas nuevas de consulta no habilitan PUT/PATCH.

| Solicitud | Resultado |
|---|---|
| Primera decisión válida | 200 y pedido realmente persistido |
| Aceptación equivalente ya aplicada | 200; ningún movimiento ni historial adicional |
| Rechazo equivalente, mismo motivo recortado | 200; ningún efecto adicional |
| Rechazo con otro motivo o aceptación contra rechazo | 409; conserva decisión original |
| Rechazo de un confirmado o logística incompatible | 409 |
| Rechazado histórico sin decisión verificable | 409 al reintentar; no inventa motivo |
| Motivo inválido o disponibilidad insuficiente | 422 y errores asociados al campo |
| Sin autenticación / sin facultad / fuera de ámbito | 401 / 403 / 404 según las rutas existentes |

La web muestra la última decisión, motivo escapado, responsable y fecha local. Los formularios mantienen Tabler y la identidad verde, exigen motivo, conservan el texto ante errores y utilizan la confirmación existente. La protección contra doble envío es una mejora adicional; la integridad depende de la transacción.

## Verificación

Pruebas aisladas en PHP 8.2 y SQLite; no se usa la base operativa para los escenarios de prueba.

Resultado: **67 pruebas seleccionadas distintas aprobadas** (14 decisiones, 1 concurrencia con ocho carreras, 19 API de pedidos, 20 QR/recepciones, 4 distribución fase 3, 3 cierre agrícola y 6 regresiones comerciales). La última ejecución de decisiones y API terminó con 33 pruebas y 472 aserciones; concurrencia con 60 aserciones.

La migración se aplicó localmente después del respaldo `storage/app/private/edt53-antes-20261119-104305.sqlite`. La comparación directa de las 136 tablas operativas anteriores no detectó cambios en sus datos; el historial nuevo comienza vacío.

- [x] Aceptación válida; stock exactamente suficiente y reintento sin duplicación.
- [x] Rechazo con motivo, actor y fecha; consulta desde ambos canales.
- [x] Motivo ausente, vacío, espacios, tipo incorrecto y longitud excesiva.
- [x] Sin autenticación, permiso revocado, rol no operativo y origen ajeno.
- [x] Estados incompatibles; confirmado no rechazable.
- [x] Intento de actualización genérica de estado y metadatos impuestos.
- [x] Acciones disponibles según rol, ámbito, estado y logística.
- [x] Reserva de distribución y descuento agrícola conservados.
- [x] Reserva previa/reintento no duplicados.
- [x] Stock insuficiente y vencimiento entre creación y aceptación.
- [x] Líneas acumuladas, presentaciones, factores históricos y saldos legados.
- [x] Rechazo pendiente conserva stock y reservas de otros pedidos: no hay reserva propia activa que liberar.
- [x] Stock físico intacto en distribución al aceptar/rechazar.
- [x] Repetición de aceptación y de rechazo sin duplicar efectos ni historial.
- [x] Motivo diferente devuelve conflicto y conserva el original.
- [x] Decisiones opuestas no coexisten.
- [x] Fallo de escritura revierte decisión, stock y programación.
- [x] Aceptación/rechazo web consultados desde API y viceversa.
- [x] Regresión de QR, firmas y recepción independiente por destinatario.
- [x] Concurrencia **real**: dos aceptaciones, dos rechazos, aceptación contra rechazo y dos pedidos compitiendo por saldo; cada caso en ambos tipos, con dos procesos, conexiones y barrera de inicio independientes.

Archivos de evidencia: `storage/logs/edt53-verificado.log`, `edt53-final.log`, `edt53-regresion.log` y `edt53-concurrencia.log`. La prueba de concurrencia ejecuta ocho carreras y comprueba estado, cantidad física e historial.

No ejecutado: suite completa, motores PostgreSQL/MySQL, PHP 8.3/8.4, Flutter o recorrido visual en navegador/dispositivo. No se afirma que CI remoto esté verde: estos cambios todavía no se han subido. No se modificaron dependencias ni el contrato de recepción QR.
