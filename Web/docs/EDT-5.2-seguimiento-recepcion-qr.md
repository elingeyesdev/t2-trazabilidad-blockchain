# EDT 5.2 · Seguimiento y recepción con QR (#49)

Implementación local del 19/11/2026, sobre EDT 5.1. Rama `feature/edt-5.2-seguimiento-recepcion-qr`. No publicada automáticamente.

## Decisiones basadas en el sistema

Se conservan `EnvioAsignacionMultiple` (agricultura → planta), `RutaDistribucion` (mayorista → PDV y planta → mayorista), sus pedidos, detalles, servicios de recepción y estados reales. No se agregan GPS, notificaciones, rutas, integraciones ni dependencias.

El usuario eligió **un QR por destinatario** para rutas de distribución mixtas. Se agrupan los pedidos de una ruta por el usuario dueño de sus puntos de venta. Cada dueño confirma solamente sus líneas; las demás recepciones quedan pendientes. La sincronización existente completa la ruta cuando todos sus pedidos son terminales. El QR general anterior no autoriza a firmar por otros destinatarios.

Reglas conservadas:

| Trayecto | Destinatario autorizado | Cantidades |
|---|---|---|
| Agrícola | Jefe responsable del almacén de planta resuelto por el servicio actual | Pesaje por todas las líneas, kg positivos, hasta seis decimales, no más de lo enviado. Un solo cierre; faltantes admitidos, sin recepciones posteriores. |
| Distribución | Minorista dueño de los PDV de sus pedidos | Recepción completa de todas sus líneas. No se añaden parciales ni tolerancias. |
| Traslado | Mayorista responsable del almacén destino | Regla MAY-14: de cero a lo despachado, hasta cuatro decimales; toda diferencia exige motivo. Un cierre. |

No existe caducidad ni revocación en `recepcion_qr_envio`; no se inventó un plazo. `qrtoken_asignacion` pertenece a otro mecanismo y no se reutiliza como autorización de recepción.

## API

Todas las rutas requieren `auth:sanctum`. La consulta se limita antes de paginar o contar. Se mantienen las respuestas 404 para envíos/recepciones de otro ámbito y 403 cuando falta permiso o representación.

`tipo` es `agricola`, `distribucion` o `traslado`.

| Método | Ruta | Uso |
|---|---|---|
| GET | `/api/envios/{tipo}` | Lista con `page`, `per_page` (1–50), filtro `estado` |
| GET | `/api/envios/{tipo}/{envio}` | Estado, destinos, pedidos/líneas, unidades, fechas persistidas y recepciones |
| POST | `/api/envios/{tipo}/{envio}/codigos` | Obtiene los QR propios; conductor asignado ve los destinatarios de su viaje |
| POST | `/api/envios/qr/resolver` | Resuelve `codigo` como secreto o URL del origen configurado; **no recibe ni consume** |
| POST | `/api/envios/{tipo}/{envio}/recepcion` | Confirma cantidades y firma con un código del mismo envío |
| GET | `/api/recepciones-envio/{recepcion}` | Consulta el resultado persistido, también si se perdió la respuesta del POST |
| GET | `/api/recepciones-envio/{recepcion}/firma` | PNG privado, sujeto al mismo ámbito |
| GET | `/api/recepciones-envio/{recepcion}/comprobante` | PDF autorizado generado bajo demanda con DomPDF ya instalado |

Consulta agrícola: permisos existentes `recepcion_planta.view`, `pedidos.view` o `asignaciones.view`, más ámbito de participación/destino. Confirmación agrícola: `recepcion_planta.confirm` y destinatario real. Distribución/traslado: `pedidos_distribucion.view` para consulta y `pedidos_distribucion.update` más destinatario real para recibir. Un administrador supervisor, remitente o transportista no puede sustituir al receptor.

Ejemplo de confirmación JSON (los IDs y cantidades se obtienen del detalle autorizado):

```json
{
  "codigo": "contenido_del_qr",
  "imagen_firma": "data:image/png;base64,...",
  "lineas": [
    {"id": 123, "cantidad_recibida": "5.123456"}
  ]
}
```

Para un traslado puede enviarse `motivo` en cada línea. Se rechazan líneas duplicadas, ajenas, faltantes, cantidades mal formadas y factores/unidades suministrados por el cliente. Firmante y fecha se determinan desde la cuenta y el servidor. El PNG debe contener tinta, ser decodificable, de hasta 1 MB y 2048 × 2048; no se presenta como firma digital certificada.

La confirmación devuelve 201 con `data`: envío, destinos, líneas enviadas/recibidas, unidades, firmante, fecha y rutas protegidas de firma/comprobante. Errores por campo: 422; código ya utilizado: 409, sin nuevas escrituras. No se incluyen secretos o rutas de disco en las respuestas de consulta.

## Persistencia y atomicidad

La migración `2026_11_19_120000_recepciones_qr_por_destinatario` amplía la tabla existente con clave única de operación/destinatario, secreto cifrado, destinatario cuando corresponde, fecha de consumo, referencia privada de firma y datos conservados de recepción. Retira la restricción de un solo QR por ruta y mantiene la asignación agrícola única y todos los registros previos. Nuevos secretos: aleatorios, búsqueda por SHA-256 y copia cifrada para volver a mostrar el QR. Los enlaces anteriores siguen siendo resolubles; el digest almacenado no se acepta como secreto.

Una transacción protege la operación y el QR, vuelve a autorizar contra los registros actuales, valida líneas/estado/firma, registra la recepción mediante los servicios existentes, aplica inventario y consume el código. En SQLite se obtiene primero el lock de escritura; en PostgreSQL se usa `FOR UPDATE`. La prueba concurrente utiliza procesos/conexiones diferentes, no dos llamadas sobre la misma conexión.

El origen agrícola ya se descontó al aceptar el pedido: no se vuelve a consumir. En distribución se reutilizan las salidas por línea y se acredita el PDV. Para pedidos con datos EDT 5.1, los ingresos conservan seis decimales, peso histórico y vencimiento de la partida, suman al saldo previo y se identifican por pedido/línea. El flujo anterior sin datos conservados permanece compatible. Traslados reutilizan la transferencia y cantidades recibidas MAY-14.

La firma se guarda en el disco `local` privado con UUID. Ante un fallo previo al commit se elimina únicamente el archivo nuevo y se revierten firma, movimientos, recepción y consumo del QR. El comprobante usa los datos persistidos, no el catálogo actual. Se genera en la consulta, sin escribir un PDF público. Las guías históricas públicas no vuelven a incrustar la firma privada de estas recepciones: un fallo al generar el PDF permite reintentar su consulta sin repetir la recepción.

La base SQLite local se migró con respaldo `storage/app/private/edt52-antes-20261119-095335.sqlite`. Se comprobaron los campos anteriores de 16 tablas relacionadas: todos conservados. El informe está en `storage/app/private/edt52-migracion-result.json`. No se añadieron usuarios o envíos de prueba a la base operativa.

## Web

El QR abre la identificación y solicita sesión; solo una cuenta autorizada ve destinos/líneas. Las nuevas recepciones web y API llaman `EnvioRecepcionQrService::confirmar`. Los detalles de pedido incorporan un acceso a recibir o al comprobante. Los paneles de cierre muestran los QR separados por destinatario y su uso. Se mantienen Tabler, barra lateral y verde. En móvil las cantidades y campos se apilan, sin desbordamiento de página. Se reutiliza el lienzo de firma y la biblioteca QR ya empleados por el sistema; no se añadió lector de cámara.

## Verificación

- [x] Consulta autorizada de estado/destino y resolución sin consumo.
- [x] Recepción válida en los tres trayectos: cantidades, unidades, firma, fecha, stock y comprobante concretos.
- [x] Remitente, transportista, administrador, usuario ajeno y permiso revocado rechazados.
- [x] QR inválido/manipulado, digest, URL ajena, pertenencia anidada y QR utilizado.
- [x] Líneas ajenas/duplicadas, cantidades inválidas, sobre-recepción, faltantes y parciales según el flujo real.
- [x] Firma ausente/vacía/truncada/formato ajeno/excesiva rechazada.
- [x] Estado incompatible; fallos de BD antes y después de crear movimientos; fallo de almacenamiento; limpieza y reintento.
- [x] Repetición sin duplicados y recuperación consultando la recepción tras perder la respuesta.
- [x] Comprobante correcto y acceso directo a firma/PDF protegido; fallo de PDF sin deshacer la recepción.
- [x] Aislamiento de destinatarios de una ruta mixta, equivalencia histórica y saldo previo.
- [x] Dos procesos sobre el mismo código: 201 y 409, una recepción, un ingreso y un archivo por caso; agricultura y distribución.
- [x] Regresiones pertinentes de EDT 5.1, reservas, firmas, cierres y seguridad de rutas.
- [x] Navegador con base aislada: escritorio 1440 y móvil 390, lienzo operativo, envío real del formulario y recepción utilizada con enlace al comprobante.

Se ejecutaron 81 pruebas pertinentes en grupos, incluidas 21 nuevas (20 funcionales y una de concurrencia), además de lint PHP, Pint y revisión de diff. Evidencias principales: `storage/logs/edt52-validacion-final.log`, `edt52-concurrencia-final.log`, `edt52-privacidad-final.log`, `edt52-regresiones.log` (su caso del parámetro enumerado se corrigió y verificó en `edt52-auth.log`). Las capturas se conservan en `storage/app/private/edt52-1440.png` y `edt52-390.png`.

No ejecutado: suite completa, PostgreSQL, PHP 8.3/8.4, CI remoto o integración Flutter de extremo a extremo. La validación local utilizó PHP 8.2 y SQLite. No hubo cambios de assets compilados que requieran Vite. No aplican pruebas de caducidad/revocación: el mecanismo actual no define esos estados.
