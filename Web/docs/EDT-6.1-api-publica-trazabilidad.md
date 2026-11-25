# EDT 6.1 API pública de trazabilidad

`GET /api/trazabilidad/{codigo}` consulta el recorrido registrado sin sesión ni token. No ejecuta recepciones, cierres, emisiones, sincronizaciones blockchain ni movimientos de inventario. La proyección pública es independiente de los Resources privados y del servicio web heredado que infiere vínculos y actualiza datos.

## Códigos y QR

Se eliminan espacios exteriores y se normaliza a mayúsculas. La búsqueda es exacta y parametrizada, también para UUID históricos almacenados en minúsculas. No se convierten prefijos ni se busca por nombre. Si dos registros coinciden después de normalizar, se responde 409 sin escoger uno arbitrariamente.

Formatos admitidos, hasta 64 caracteres ASCII:

- `TRAZ-YYYYMMDD-XXXXXX`: formato agrícola generado actualmente por `LoteDefaults`.
- `TRZ-YYYYMMDD-XXXXXX`: compatibilidad agrícola solicitada; debe existir exactamente con ese prefijo.
- `TRZ-PDV-YYYYMMDD-XXXXXX`: formato PDV de seis caracteres alfanuméricos.
- `TRZ-PDV-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`: formato UUID usado por recepciones conservadas.

Primero se resuelve el prefijo PDV en `insumo`; los otros se buscan en `lote`. Los QR de trazabilidad existentes contienen una URL de la web `/trazabilidad/{codigo}`. El cliente extrae y decodifica su último segmento y envía sólo ese código a esta API. No se descargan URLs recibidas ni se aceptan tokens de QR de recepción como códigos de trazabilidad.

Ejemplos de consulta con los códigos del fixture aislado:

```sh
curl -i http://127.0.0.1:8001/api/trazabilidad/TRAZ-20261124-ABC123
curl -i http://127.0.0.1:8001/api/trazabilidad/TRZ-PDV-20261124-DEF456
```

Un código bien formado inexistente devuelve 404 JSON con `message`; uno mal formado o excesivamente largo, 422 JSON con `errors.codigo`. La ruta conserva JSON aunque no se envíe `Accept`. Una URL completa no es un código y no se utiliza como destino de red.

## Contrato y procedencia

La respuesta es plana: `codigo`, `tipo` (`lote_agricola` o `pdv`), `producto`, `origenes`, `etapas`, `rutas`, `evidencias`, `estado_evidencias`, `certificaciones` y `blockchain`.

`etapas` contiene siempre `agricola`, `planta`, `mayorista`, `distribucion`, `pdv`, en ese orden. Cada etapa tiene `estado` y `eventos`; sin registros se devuelve `sin_informacion_registrada` y `[]`. El modelo no permite afirmar automáticamente que una etapa vacía sea «no aplicable».

Los eventos se ordenan por fecha de negocio y referencia determinista; las fechas ausentes se colocan al final. Se distinguen programación, registro, cierre y recepción. Las fechas de salida que el modelo no distingue de una programación se identifican como tales, sin presentarlas como ejecución comprobada. Las cantidades se representan como cadenas decimales de seis posiciones y las fechas conservan precisión de día u hora según su fuente. `null` significa que el valor no está registrado.

Los vínculos usan claves reales: partidas PDV del insumo y almacén consultados → lote industrial → consumos → materia prima recibida → detalle agrícola → almacenamiento de cosecha → producción → lote. Los consumos industriales relacionados se recorren con control de ciclos. Los eventos agrícolas son contexto del lote de origen, no prueba de que una actividad se ejecutara sobre una unidad particular de producto.

Se preservan múltiples orígenes y productos con referencias separadas y se deduplican eventos. Compartir nombre de producto, catálogo, ruta o fecha no crea parentesco. Las recepciones PDV actuales conservan el FK del detalle en la salida, no en la entrada destino. Para recuperar ese enlace se exige el número de pedido explícito del movimiento, destino exacto, referencia de partida no vacía e idéntica, proceso industrial coincidente, partida de origen inequívoca y cantidades históricas verificadas contra un QR ya utilizado con los IDs del pedido y detalle correctos. La referencia textual sola no basta. Si faltan esas pruebas o hay ambigüedad se conserva el recorrido parcial. Una llegada a la ruta completa tampoco acredita recepción por un destinatario.

Se cargan relaciones por lotes y no se truncan las colecciones con límites silenciosos. No hay caché de la proyección; la respuesta usa `Cache-Control: no-store, private` para reflejar retiros y cambios de certificación.

## Certificación y blockchain

Se publican únicamente emisiones ligadas por FK a los lotes del recorrido. Se conserva el historial y sus fechas; no existe una regla persistida de vigencia, caducidad o revocación, por lo que `vigencia` es `no_determinada`. Un proceso completado no crea una certificación. Los resultados se limitan a los valores estructurados existentes; narrativas antiguas quedan fuera.

Blockchain representa registros locales, no una comprobación de red en vivo: `fuente: registro_local`, `verificado_en_vivo: false`. Los estados existentes son `pendiente`, `certificada`, `rechazada`, `error`, `omitida` y la compatibilidad histórica `confirmado`. La confirmación registrada utiliza la regla existente de estado y transacción, nunca la mera existencia de un hash.

`hash_payload` corresponde al SHA256 del payload canónico; no es el hash del PDF. `hash_transaccion` es una referencia diferente. No se persisten red, hash de bloque, hash de documento ni última comprobación del proveedor: esos campos son `null`; tampoco se fabrican enlaces a exploradores. No se llama al proveedor ni al servicio de sincronización que escribe estados.

Extracto del contrato cuando no hay emisiones ni evidencias aprobadas:

```json
{
  "evidencias": [],
  "estado_evidencias": "sin_evidencias_publicas_disponibles",
  "certificaciones": {"estado": "sin_certificacion_registrada", "emisiones": []},
  "blockchain": {"estado": "sin_respaldo_registrado", "registros": []}
}
```

## Publicación explícita de fotografías

Todos los archivos quedan excluidos de la API por defecto. El control mínimo admite las fotografías locales de actividades realmente vinculadas; no publica PDFs, firmas, comprobantes ni archivos arbitrarios. Ninguna migración o consulta aprueba archivos automáticamente.

El jefe agricultor solicita dentro de sus lotes/equipo. El jefe de planta puede revisar y solicitar fotografías de un origen agrícola que esté ligado por FK a una producción de su ámbito, indicando ese contexto. El administrador necesita el permiso específico `evidencias.publicar` para aprobar o retirar. La migración y la matriz añaden sólo ese permiso de gobierno al administrador, conservando sus demás permisos y la separación de operaciones de negocio.

Endpoints privados, todos con `auth:sanctum` y autorización de ámbito en el servidor:

| Método y ruta | Uso |
|---|---|
| `GET /api/evidencias-publicacion` | Listado paginado del ámbito autorizado, con historial interno |
| `POST /api/evidencias-publicacion/actividades/{actividad}/solicitar` | Solicitar publicación con `motivo`; contexto de planta opcional `loteproduccionpedidoid` |
| `GET /api/evidencias-publicacion/{publicacion}/archivo` | Revisar el original dentro del ámbito autorizado |
| `POST /api/evidencias-publicacion/{publicacion}/aprobar` | Aprobación administrativa explícita con `motivo` |
| `POST /api/evidencias-publicacion/{publicacion}/solicitar-retiro` | Solicitar retiro con `motivo` |
| `POST /api/evidencias-publicacion/{publicacion}/retirar` | Retiro administrativo con `motivo` |

El motivo es obligatorio, hasta 1000 caracteres. La auditoría conserva actor, fecha, acción y motivo. Los reintentos equivalentes no duplican aprobaciones ni retiros. Una petición de retiro permanece publicada hasta la decisión administrativa; al retirarla desaparece de la API y su enlace responde 404. El historial y la copia revisada se conservan internamente.

Sólo se admite una publicación activa por fotografía, incluso si llegan solicitudes desde contextos distintos. Aprobar otra mientras exista una activa devuelve 409; así, retirar una copia no reactiva silenciosamente una anterior. Una nueva publicación después del retiro necesita otra solicitud y aprobación explícitas.

Las cuentas deben estar activas y aprobadas. Los jefes necesitan también el permiso efectivo de consulta del origen; el rol por sí solo no recupera permisos revocados.

Se verifica la huella de la versión solicitada. La aprobación recodifica JPG, PNG o WebP (máximo 5 MB y 20 megapíxeles) a una nueva imagen PNG sin EXIF, comentarios ni metadatos heredados. La revisión humana debe comprobar también que los píxeles no contengan personas, firmas, direcciones, coordenadas u otros datos privados. La recodificación no sustituye esa revisión. Si cambia la fotografía original se requiere otra solicitud; un archivo ausente no rompe la consulta.

Las copias permanecen en disco privado y sólo se sirven mediante `GET /api/trazabilidad/evidencias/{token}` mientras estén aprobadas y disponibles. El token de este enlace público no es un token de recepción y no autoriza ninguna operación. La respuesta no expone rutas de disco ni motivos, actores o historial de aprobación. El enlace usa `no-store` para no conservar acceso tras un retiro.

## Límite y privacidad

Ambos GET públicos usan el limitador `trazabilidad-publica`: 60 solicitudes por minuto, con 429 JSON y encabezados de reintento. La clave usa `REMOTE_ADDR`, no `X-Forwarded-For` ni otros encabezados enviados por el cliente. En una instalación detrás de un proxy, los clientes que compartan ese par de conexión comparten cuota; la identidad de red debe resolverse mediante infraestructura confiable antes de ampliar este criterio. No se cambian proxies globales ni CORS.

La proyección excluye usuarios y sus IDs, correos, teléfonos, ubicaciones precisas, notas, incidencias privadas, firmas, credenciales, QR de recepción, instantáneas privadas de certificados y secretos blockchain. Las rutas sólo muestran referencias, tipo, estado y fechas; no domicilios, coordenadas ni posición en vivo. Los endpoints privados mantienen sus permisos.

## Verificación

Pruebas Feature aisladas: `TrazabilidadPublicaApiTest`, `CertificacionPublicaTest`, `EvidenciaPublicacionTest` y `RecorridoPublicoRutasTest`. Cubren acceso anónimo, formatos, errores JSON, duplicados, multiorigen, precisión, datos parciales, hashes/estados, 429 resistente a encabezados falsos, ausencia de escrituras de negocio y privacidad con valores reconocibles de usuarios, QR, firmas e incidencias. El flujo de publicación comprueba aprobación, sanitización, ámbito, cambio de archivo, retiro y auditoría.

En la instalación local se aplicó la migración con respaldo privado `storage/app/private/edt61-antes-20261124.sqlite`; se comprobaron 133 tablas operativas sin cambios y la conservación de permisos previos. No se aprobó ningún archivo. Se comprobó por HTTP un código agrícola existente, con 200 anónimo, y se compiló la caché de rutas en un archivo de comprobación independiente.

No se realiza una verificación blockchain en vivo, ni escaneo Flutter, rediseño web, publicación automática de archivos o despliegue. PHP 8.3/8.4 y un recorrido Flutter completo requieren sus entornos correspondientes.
