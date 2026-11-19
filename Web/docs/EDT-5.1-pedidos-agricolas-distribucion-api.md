# EDT 5.1 — Pedidos agrícolas y de distribución desde la API

## Diagnóstico y alcance

En este proyecto `Pedido` representa el envío agrícola hacia planta, con referencias a cosechas almacenadas o material de siembra. `PedidoDistribucion` representa el abastecimiento de un punto de venta desde almacenes mayoristas. Se conservan ambos modelos y sus diferencias; no se agregan rutas de transporte, pagos, facturación, estados ni paquetes.

La API agrícola anterior devolvía modelos completos sin acotar el usuario y permitía asignar estados arbitrarios. Distribución tenía su flujo comercial en la web, sin API propia. La creación web y API ahora comparten `PedidoAgricolaCreacionService` y `PedidoDistribucionCreacionService`; `PedidoEntradaService` centraliza precisión y comprobación acumulada, `PedidoTransicionService` las acciones, y `PedidoMovilAcceso` las consultas autorizadas. El Resource selecciona campos explícitos.

## Contrato

Todas las rutas requieren Sanctum. Se usa el prefijo `/api` existente.

| Ruta | Operación | Permiso |
| --- | --- | --- |
| `GET /pedidos-agricolas` | Lista paginada | `pedidos.view` |
| `POST /pedidos-agricolas` | Crear envío agrícola | `pedidos.create` y jefe agrícola |
| `GET /pedidos-agricolas/{id}` | Detalle autorizado | `pedidos.view` |
| `POST /pedidos-agricolas/{id}/transiciones` | Acción agrícola | `pedidos.update` y jefe agrícola |
| `GET /pedidos-distribucion` | Lista paginada | `pedidos_distribucion.view` |
| `POST /pedidos-distribucion` | Crear solicitud/envío | `pedidos_distribucion.create` y minorista/mayorista operativo |
| `GET /pedidos-distribucion/{id}` | Detalle autorizado | `pedidos_distribucion.view` |
| `POST /pedidos-distribucion/{id}/transiciones` | Acción comercial | `pedidos_distribucion.update`, rol y pertenencia |

Listas: `data`, `links`, `meta`; admiten `page`, `per_page` de 1 a 50 y `estado`. Los filtros se aplican sobre la consulta autorizada, incluidos sus conteos. Detalle/creación: objeto en `data`; crear devuelve 201. Las cantidades nuevas son cadenas con seis decimales. Fechas ISO, campos desconocidos en `null` y colecciones vacías en `[]`.

La respuesta identifica tipo, ID, número, estado persistido, fechas, autor y aceptación, destino y líneas. Cada línea identifica producto, presentación/calibre, cantidad/unidad, equivalencia conservada cuando existe y origen. No se devuelven modelos completos, huellas de reintento, contraseñas ni rutas de archivos. En agrícola, `envio` informa separadamente el estado logístico y la recepción en planta: no sustituye el estado de aprobación del pedido. En distribución se conservan los indicadores y fechas del envío iniciado por mayorista y la confirmación del minorista.

`/api/pedidos` mantiene las claves originales (`pedidoid`, `detallepedidoid`, etc.) y las respuestas planas. La lista queda paginada sin introducir una envoltura: `page`, `per_page` y cabeceras `X-Total-Count`/`X-Current-Page`. Sus lecturas también se acotan. Las escrituras antiguas sin origen verificable o con estado/autoría enviados libremente ya no son aceptadas: deben cumplir el flujo de creación web. PATCH/PUT genérico rechaza reemplazos de estado y líneas; DELETE genérico no elimina pedidos. Para el contrato nuevo de cantidades exactas se utilizan las rutas específicas anteriores.

### Crear agrícola

Conserva los campos del formulario actual: origen y destino GPS (`origen_latitud`, `origen_longitud`, `latitud`, `longitud`), `origen_almacenid`, direcciones opcionales, `fechaEntregaDeseada`, transportista, vehículo y `costo_bs` del envío. Se reutilizan las validaciones existentes de flota, licencia, disponibilidad y capacidad. Se mantienen recogidas adicionales y sus coordenadas; no se agrega un flujo logístico distinto.

`detalles[]` contiene:

- `producto_ref`: `cosecha:{produccionalmacenamientoid}` o `insumo:{insumoid}` de material de siembra elegible, dentro del ámbito agrícola propio.
- `cantidad`: kg solicitados, conforme al contrato logístico existente. Se comprueba el acumulado por origen. La conversión a la unidad física de origen utiliza el factor conservado de la cosecha o la equivalencia verificable del servidor; la cantidad debe ser representable con seis decimales en esa unidad.
- `observaciones`: presentación descriptiva del flujo existente, con el formato `@carga:…@` generado por `PedidoCatalogo::construirMetaCargaObservaciones`. Este texto no decide la cantidad física ni el factor de conversión.
- `catalogotamanoconteoid`, opcional: debe corresponder a la cosecha o material seleccionado. La presentación/calibre conservada se obtiene del servidor cuando existe el vínculo.
- `materiaprimaloteid`: necesario para material de siembra registrado por partidas. Debe pertenecer al mismo insumo y almacén, estar habilitado y no vencido. El formulario web incorpora el selector; no se elige automáticamente una partida distinta.

Un `cultivo:{id}` de catálogo no identifica existencias y se rechaza para pedidos nuevos. No se simula stock a partir de su nombre. El destino agrícola conserva la estructura real de coordenadas/dirección del modelo: se valida GPS y el trayecto autorizado, sin inventar un almacén destino a partir del texto. En distribución, el destino sí es una entidad `PuntoVenta` y se valida su pertenencia y actividad.

### Crear distribución

Campos: `puntoventaid`, `fecha_entrega_deseada`, hora/observaciones opcionales, `almacen_mayorista_origenid` según el flujo, y `detalles[]` con `insumoid`, `insumo_presentacionid`, `cantidad` en envases y, cuando se selecciona, `inventario_presentacion_loteid`. Se mantiene la compatibilidad del formulario de una línea y la colección de varias líneas.

El minorista solo utiliza sus puntos de venta. El mayorista inicia desde sus almacenes, con canal externo, transportista y vehículo como exige la web; autoría, aprobación y estado inicial los determina Laravel. Todas las líneas deben abastecerse de un mismo mayorista responsable, aunque haya varios almacenes. Se comprueban producto terminado, presentación activa del producto, partida compatible y capacidad del punto de venta con los servicios existentes.

Se conserva por línea la presentación, unidad y equivalencia en kg calculada con valores del servidor. No se aceptan `cantidad_kg`, `cantidad_base`, `peso_neto_kg`, snapshots, propietario ni estados iniciales protegidos enviados por el cliente. La equivalencia registrada se mantiene si cambia posteriormente el catálogo; una edición autorizada vuelve a comprobar la solicitud y actualiza su cantidad derivada. La web muestra todas las líneas y conserva los decimales.

## Inventario, transacciones y reintentos

| Momento | Agrícola | Distribución |
| --- | --- | --- |
| Creación | Valida; no descuenta ni asegura inventario futuro | Solicitud minorista valida sin reservar; envío iniciado por mayorista nace confirmado y reserva |
| Aceptación | Revalida y descuenta físicamente el origen, como el flujo anterior denominado «reserva» | Revalida y reserva mediante el estado confirmado; todavía no descuenta |
| Inicio de ruta | El material ya fue descontado al aceptar | El servicio existente descuenta por línea/partida y registra la salida |
| Rechazo/revisión | Rechazo solo antes de aceptar; no hay descuento que devolver | Rechazo pendiente no reserva; volver a revisión libera la reserva derivada del estado |

Una solicitud pendiente no garantiza existencias futuras. Se comprueban acumulados por producto, presentación y partida, incluidos vencimientos, bloqueos y reservas. No se mezclan kg y envases. La confirmación comprueba nuevamente el estado y saldo dentro de la transacción. Los bloqueos de producto utilizados por inventario serializan las reservas y consumos; SQLite toma un bloqueo de escritura antes de leer el estado que se cambiará. Cabecera, líneas, almacenaje de destino cuando lo genera el servicio existente, reserva y asignación relacionadas se revierten ante errores.

`solicitud_id` UUID opcional permite reintentar **creaciones** por usuario y tipo de pedido. Misma clave y contenido devuelve el mismo ID con 201; contenido distinto devuelve 409. Sin clave, dos pedidos iguales son solicitudes independientes. No se deduce idempotencia solamente del contenido. Las acciones repetidas sobre el estado ya alcanzado no vuelven a consumir ni reservar. La salida existente conserva su identificación por línea para no duplicar movimientos.

## Transiciones encontradas

El cuerpo de transición contiene `accion` y, para rechazar, `motivo_rechazo` opcional. No permite reemplazar estado, cantidades, pertenencia o líneas.

| Tipo / actor | Acción | Precondición y efecto |
| --- | --- | --- |
| Agrícola / jefe agrícola del ámbito | `aceptar` | `sin asignacion` o `pendiente`, envío programado y material utilizable; queda `confirmado`, con fecha/actor y descuento único |
| Agrícola / jefe agrícola del ámbito | `rechazar` | Pendiente; queda `rechazado` y se cancela el envío asociado |
| Distribución / mayorista del origen | `aceptar` | Pendiente; queda `confirmado` con reserva. Se conserva el flujo legado de coordinación con planta cuando corresponde a registros anteriores |
| Distribución / mayorista del origen | `rechazar` | Pendiente; queda `rechazado` |
| Distribución / mayorista del origen | `reabrir-revision` | Confirmado y permitido por el catálogo actual; libera la asignación existente y vuelve a `pendiente` |
| Distribución / minorista dueño | `confirmar-envio-mayorista` | Envío iniciado por mayorista pendiente de su aprobación; registra la fecha sin inventar otro estado |

Despacho, tránsito y recepción continúan por sus mecanismos operativos, con sus requisitos. No se agrega un setter de `en_transito`/`recibido` que omita transporte o cierre. El administrador supervisa sin operar. Pedido ajeno: 404 en API; se preservan los controles 403 existentes en las acciones web de distribución. Los vínculos de productos, partidas, origen y destino se comprueban además del permiso de la cabecera.

## Migración

`2026_11_19_100000_conservar_solicitudes_pedidos_api` agrega autoría agrícola nullable, solicitud/huella por cabecera, datos de solicitud por línea y el FK opcional a la partida agrícola de material. Amplía cantidades de líneas a `NUMERIC(18,6)`; SQLite utiliza texto para evitar su conversión a float, conforme a la estrategia de cosechas e inventario del repositorio. No se rellenan autorías, factores ni relaciones históricos. La reversión requiere preservar manualmente esos datos.

Se aplicó localmente con respaldo SQLite consistente. Se compararon todos los campos previos de pedidos, líneas, envíos, usuarios, inventario, movimientos y certificados: permanecieron iguales. Las cantidades de líneas se compararon mediante su representación SQL en texto al cambiar la afinidad. No se ejecutaron borrados ni se modificaron emisiones históricas.

## Verificación

- [x] Creación y consulta agrícola por API, con referencias reales.
- [x] Creación y consulta de distribución por API, incluidas varias líneas.
- [x] Productos, presentaciones, cantidades, unidades y destino persistidos y visibles en web.
- [x] Validación acumulada y disponibilidad real, con reservas, vencimientos y partidas bloqueadas.
- [x] Acciones autorizadas, control del estado actual y reintentos sin duplicar efectos.
- [x] Consulta cruzada API → web y web → API, preservando los flujos existentes.

**49 pruebas pertinentes distintas aprobadas**, en PHP 8.2 y bases SQLite aisladas:

- `ApiPedidosMovilTest`: 19 métodos cubren ambos tipos, creación/listado/detalle, persistencia, precisión y cantidades inválidas, presentación/destino ajenos, stock exacto e insuficiente, líneas acumuladas, distintas presentaciones, fechas y bloqueos, reservas y revisión, campos protegidos, permisos y ámbitos, reintentos/conflicto, fallos de guardado y reversión de descuento, semilla por partida, compatibilidad de respuesta legada y consultas cruzadas. También comprueba un despacho repetido y un cambio posterior del peso de catálogo.
- `PedidosMovilConcurrenciaTest`: una prueba con dos procesos PHP y conexiones independientes para cada tipo. De dos pedidos de seis unidades sobre diez disponibles, solo uno se acepta: agrícola queda con cuatro; distribución conserva diez físicas y una única reserva confirmada.
- Regresiones: `Frente3PedidosTest` (6), `PedidoDistribucionFase3Test` (4), `PedidosAccessTest` (1) y `ApiPlantaTrabajoTest` (18).

Edge revisó el detalle con dos líneas a 1440 y 390 px, sin desbordamiento de página ni excepciones JavaScript. Se comprobó el selector de material en una fila real del formulario: selecciona una sola partida y la incluye en `FormData`. Evidencia local en `storage/app/private/edt51-*`, ignorada por Git. Se conservaron los componentes y estilos de Tabler; no hubo cambios de assets que requirieran Vite.

Se ejecutaron sintaxis PHP, Pint en los archivos nuevos y `git diff --check`. No se ejecutó la suite completa, PostgreSQL, PHP 8.3/8.4 ni Flutter de extremo a extremo. El módulo Flutter de pedidos sigue siendo un acceso pendiente de pantallas propias; esta entrega prepara la API y comprueba Laravel/web, sin afirmar una prueba móvil completa. No se publicaron cambios en GitHub.
