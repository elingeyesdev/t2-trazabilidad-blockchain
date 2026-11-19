# EDT 4.4 — Historial de certificados y antecedentes del producto

## Emisiones conservadas

Se reutilizan `certificacion_lote` (campo) y `evaluacion_final_lote_produccion` (planta). Cada emisión crea una fila nueva, con su PK original, código único, ULID, fecha del servidor, emisor, resultado, observaciones, recomendaciones, instantánea JSON, versión documental y referencia privada al PDF. Las consultas ordenan por fecha descendente y PK descendente para resolver empates.

`CertificadoEmisionService` centraliza los POST existentes de campo (web, lote/batch y API) y planta (web). Conserva los requisitos operativos, permisos y cierre único de etapas de EDT 4.3. Una evaluación posterior se registra desde el historial o detalle; no actualiza la fila anterior. Una nueva evaluación no conforme tampoco elimina almacenajes históricos.

Los códigos de campo mantienen los prefijos CERT/NCONF y año/lote; se añade un ULID para distinguir emisiones. En planta se utiliza PLANTA/año/lote/ULID. Son identificadores únicos, no una numeración consecutiva legal. Las restricciones únicas de la base respaldan la identificación.

Las actualizaciones de los modelos protegen los campos emitidos y su archivo. Los borrados de certificados se rechazan. Las FK de los lotes asociados y del inspector de planta restringen el borrado; los servicios de eliminación dejan de borrar certificados mediante Query Builder. Los campos técnicos de la integración blockchain existente pueden actualizarse sin cambiar el documento o la instantánea. Esto es protección de aplicación y conservación documental, no inmutabilidad criptográfica ni protección frente a administradores de la base.

## Instantánea frente a recorrido actual

`datos_emision` conserva los valores necesarios del documento y los IDs de origen. No se reconstruye un certificado anterior desde nombres, cantidades o parámetros actuales. La versión inicial del PDF es `CertificadoDocumentoService::VERSION = 1`, con la plantilla `certificados/documento-v1`. Se utiliza Dompdf ya instalado, sin recursos remotos ni dependencias nuevas.

Las cantidades se conservan individualmente con su unidad y precisión registrada; no se totalizan materias primas u orígenes diferentes. Las cantidades consumidas mantienen la precisión que admite el flujo existente; los parámetros de EDT 4.3 conservan `valor_decimal`. El resumen de la integración de campo no suma cosechas de unidades distintas. Su payload de nuevas emisiones se fija en la instantánea y completa únicamente la PK del certificado al enviarse. No se implementa una integración blockchain nueva.

`ProductoAntecedentesService` consulta **datos actuales**, con autorización desde el lote inicial:

| Inicio | Dirección y datos disponibles |
| --- | --- |
| Lote agrícola | Cultivo, superficie/unidad, ubicación y siembra; actividades con tipo, orden, fechas, cierre y responsable; todas sus producciones/cosechas con IDs, cantidad, cantidad base, unidad y presentación registrada. |
| Lote de producción | Pedido y plantilla; todas las líneas `LoteProduccionMateriaPrima`; insumo/unidad, cantidades, partida y vencimiento; partida → `detallePedido` → pedido → envío y su línea de recepción registrada; almacenamiento/cosecha/lote agrícola de origen cuando sus IDs están disponibles. |
| Material proveniente de presentación industrial | `presentacionLote` → ID del lote de producción de origen, sin sustituirlo por un origen agrícola supuesto. |
| Etapas de planta | Registros con proceso, máquina, asignación, fechas, responsable y parámetros medidos conservados por EDT 4.3. |
| Emisiones | Relaciones `certificaciones()` / `evaluacionesFinales()`, fecha, ID y acceso a su instantánea independiente. |

Los orígenes son uno a varios: cada línea se conserva por separado, sin escoger arbitrariamente la primera. Se selecciona únicamente la línea de recepción cuyo `detallepedidoid` corresponde a la partida. No se enlaza por nombre ni fecha. Las ausencias permanecen como nulas; no se infiere un origen para inventario antiguo. Los IDs agrícolas disponibles en una recepción autorizada no habilitan a consultar datos internos de lotes ajenos. Los orígenes industriales se presentan por ID, sin recursión indiscriminada.

## Consistencia, archivos e idempotencia

1. Una transacción breve autoriza y valida el lote y obtiene un recorrido consistente. Se bloquea el lote; SQLite adquiere escritura antes de leer y PostgreSQL utiliza REPEATABLE READ. Las solicitudes del mismo emisor se coordinan también mediante su fila en PostgreSQL.
2. Se genera y guarda el PDF **fuera** de los bloqueos de producción.
3. Una segunda transacción vuelve a comprobar autorización, requisitos, solicitud y recorrido. Si cambió la información, rechaza la emisión y limpia únicamente el archivo nuevo. Si coincide, inserta la emisión/instantánea y sus cambios de estado relacionados.
4. La integración existente se encola después de confirmar. Su fallo no destruye un documento confirmado.

`solicitud_id` es un UUID opcional por intención. Misma clave, emisor, lote y contenido devuelve la emisión previa; misma clave con otro contenido produce HTTP 409. Una intención nueva usa otra clave. Los formularios incorporan la clave; el batch deriva una clave por lote desde la del envío. Los clientes sin clave mantienen compatibilidad y cada POST es una intención nueva. El índice único emisor/solicitud respalda los reintentos concurrentes; ante una inserción duplicada se recupera la emisión confirmada con la misma huella.

Los PDFs están en el disco privado `local`, dentro de `certificados/campo|planta/ULID.pdf`. La API no revela el path ni las huellas de solicitud. La descarga verifica sesión, permiso, ámbito, referencia válida y existencia; devuelve el archivo seleccionado sin regenerarlo. Un archivo ausente responde 404. Un fallo de generación/guardado no confirma un certificado. Un fallo posterior limpia el nuevo archivo solo tras comprobar que no está referenciado; si esa comprobación falla por indisponibilidad de la base, se conserva para revisión y se registra un aviso. No se borra un archivo confirmado para intentar compensar un fallo.

## Consulta web y API

La web reutiliza Certificaciones y sus modales. «Abrir en página completa» da acceso al documento y al historial por lote; el historial tiene paginación, vacío y registro de nueva emisión. Conserva el layout Tabler y los colores existentes. Las tablas tienen contenedor desplazable en pantallas pequeñas.

Todas las rutas requieren autenticación y los permisos existentes. Campo combina `certificaciones.view/create` con `LoteAcceso`; planta usa `lote_produccion.view/update` y alcance explícito por almacenes, asignación o inspector previo. Administrador mantiene supervisión; operario no obtiene acceso a certificados privados por el permiso de consultar tareas. Las rutas anidadas comprueban también que el certificado pertenece al lote solicitado.

| API autenticada | Uso |
| --- | --- |
| GET/POST `/api/certificaciones` | Lista autorizada / emisión de campo mediante servicio común. Conserva respuesta de lista y objeto de creación. |
| GET `/api/certificaciones/{id}` y `/archivo` | Metadatos y PDF privado seleccionado de campo. |
| GET `/api/lotes/{lote}/certificados` y `/{id}` | Historial paginado y detalle anidado de campo. |
| GET `/api/planta/lotes-produccion/{lote}/certificados` y `/{id}` | Historial paginado y detalle anidado de planta. |
| GET `/api/planta/certificados/{id}/archivo` | PDF privado de planta. |
| GET `/api/lotes/{lote}/antecedentes` | Recorrido agrícola actual y IDs ordenados de emisiones. |
| GET `/api/planta/lotes-produccion/{lote}/antecedentes` | Recorrido industrial actual y IDs ordenados de emisiones. |

`CertificadoEmisionResource` distingue `instantanea` (histórica), `instantanea_disponible`, `archivo_disponible` y `formato_version`. Las relaciones resumidas `lote` y `usuario` en certificados de campo son **actuales**; no reemplazan la instantánea. Se excluyen datos de autenticación, correos, rutas privadas y el payload técnico interno. El estado de integración es actual. No se añade un endpoint público ni una API de emisión industrial que no existía.

## Antecedentes anteriores y límites

La migración añade campos nulos y restringe FK; no rellena documentos antiguos con datos actuales ni inventa emisores o fechas. Los IDs, códigos, resultados, observaciones y fechas existentes permanecen. Una emisión sin instantánea/archivo se identifica expresamente; no tiene descarga ficticia. El detalle histórico muestra solo valores originales disponibles; los modales antiguos etiquetan claramente los datos relacionados actuales. La migración rechaza la reversión automática con un mensaje explícito para impedir borrar antecedentes o marcar falsamente la migración como revertida. Una reversión requiere un procedimiento manual que preserve los datos y documentos.

La iteración 6 puede reutilizar las relaciones y el servicio autorizado para la consulta final. Quedan pendientes su presentación final, decisiones de acceso público, recorrido recursivo entre lotes y tratamiento de huecos de datos antiguos. No se añade portal, QR ni evidencia blockchain inexistente. La nueva evaluación no reemplaza un procedimiento de retiro/revocación de inventario ya despachado.

## Validación

Las pruebas usan bases aisladas y cubren emisiones sucesivas, conservación tras cambios de producto/responsables/parámetros/relaciones, archivos seleccionados, solo lectura, FK, varios orígenes, aislamiento, rutas anidadas, legacy, errores de PDF/almacenamiento/persistencia y cambio durante generación. Dos procesos PHP independientes prueban reintento simultáneo y emisiones intencionales simultáneas con códigos y archivos propios. Se comprueba también la integración congelada y el cierre único de EDT 4.3 mediante regresión.

Resultados locales (PHP 8.2.4 / SQLite):

- Suite completa: **507 correctas, 0 fallidas, 1 omitida**, 5947 aserciones. La omitida requiere una base SQLite persistida y no corresponde a las bases aisladas de la suite.
- Comprobaciones posteriores: 3 correctas sobre historial/eliminación/legacy y 3 correctas sobre unidades incompatibles, payload histórico y hash canónico. Incluyen los casos añadidos tras iniciar la suite completa.
- Pruebas de concurrencia de EDT 4.4 y regresión de EDT 4.3 incluidas en la suite, con procesos PHP independientes.
- Pint en los archivos nuevos y comprobación de diferencias sin errores; compilación Blade correcta. No se recompilan assets porque no cambian JavaScript, CSS ni entradas Vite.
- Edge: historial y detalle de campo, detalle de planta, escritorio de 1440 px y móvil de 390 px; sin excepciones JavaScript ni desbordamiento de la página. Descarga autenticada del PDF: HTTP 200 / application/pdf. Capturas y resultado conservados localmente en storage privado ignorado por Git; base y usuarios de revisión eliminados.
- Migración local aplicada con respaldo privado previo: **16 antecedentes originales**, sin diferencias en sus columnas anteriores ni reconstrucción histórica.

La matriz remota PHP 8.3/8.4 y PostgreSQL no se han ejecutado; no se dan por comprobadas mediante SQLite/PHP 8.2. No se ejecutó Flutter ni se modificó Mobile en este EDT. Los cambios no se han publicado en GitHub.
