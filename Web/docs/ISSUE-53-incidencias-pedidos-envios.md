# Issue #53: incidencias de pedidos y envíos

## Responsables y permisos confirmados

Se amplía el módulo `IncidenteEnvio` existente. No se crea otro módulo ni se atribuye una numeración EDT al título incompleto.

El usuario confirmó responsables por ámbito: jefe agricultor para pedidos y envíos agrícolas, jefe de planta para traslados desde sus almacenes de planta, y mayorista para pedidos y rutas de distribución de sus almacenes. Se comprobaron los roles reales `jefe_agricultor`, `jefe_planta`, `mayorista` y su alias existente `jefe_mayorista`.

La matriz y una migración aditiva conceden a esos roles los permisos existentes `incidentes.view`, `incidentes.update` e `incidentes.resolve`. No se crean roles ni se sincroniza el administrador, ni se retiran permisos previos. El transportista conserva registro y consulta en sus viajes, y la edición de su propio reporte; no puede asignar posteriormente ni resolver por su sola asignación al viaje. La selección inicial al reportar solo admite responsables elegibles del ámbito correspondiente. No se asignan personas automáticamente ni se reasignan responsables registrados. El menú lateral ofrece acceso al listado según el permiso efectivo de consulta.

## Modelo y flujo

- Tipos principales admitidos: `pedido_agricola`, `pedido_distribucion`, `envio_agricola`, `traslado`, `distribucion`. Cada tipo utiliza una relación concreta; no se aceptan clases ni tablas del cliente.
- Se exige descripción de hasta 3000 caracteres y responsable elegible. El autor y estado inicial `abierto` proceden del servidor.
- La elegibilidad exige cuenta activa, aprobada o sin estado histórico, permiso efectivo `incidentes.resolve`, rol de atención correspondiente y acceso a la operación afectada. Tener un permiso directo de resolución no convierte a un conductor en responsable de atención.
- Autor, responsable y usuario que resuelve son campos distintos. No hay reasignación ni reapertura.
- `abierto` y `pendiente` muestran «Pendiente de resolución». `resuelto` conserva explicación, fecha y usuario. Otros estados históricos no se reclasifican automáticamente.
- Resolver exige una explicación de hasta 2000 caracteres y permisos sobre la incidencia concreta. Una transacción bloquea la lectura del estado: un reintento equivalente conserva los datos confirmados; otra solución devuelve 409. Una actualización genérica no puede cerrar la incidencia.
- Registrar, consultar y resolver no modifican pedidos, existencias, recepciones ni QR.

## Acceso y compatibilidad

Web y API comparten servicios de referencias, consulta y seguimiento. Los permisos de incidencias se comprueban además del ámbito de la operación. El administrador mantiene su consulta supervisora, sin escritura operativa.

Los destinatarios de rutas mixtas consultan incidencias de sus propios pedidos, sin acceder por compartir ruta a incidencias de otros destinatarios o de la ruta completa. Los conteos existentes del panel se restringen al mismo ámbito; no se añaden incidencias a los indicadores de EDT 5.5.

Las referencias históricas sin tipo no se infieren a partir de códigos ambiguos. Se preservan sus valores originales, pero no se revelan códigos o relaciones sin autorización comprobada. La consulta histórica queda restringida al administrador, autor o pedido agrícola autorizado sin referencia de envío. No se rellena automáticamente el responsable.

La primera migración añade relaciones y responsable admitiendo valores nulos para conservar antecedentes. En la base local se aplicó con respaldo privado `storage/app/private/issue53-antes-20261120.sqlite`; se verificó que los 13 antecedentes conservaran todos sus campos originales. La segunda migración solo añade los tres permisos de atención a los roles aprobados y existentes; se verifica por separado que preserve permisos del administrador, transportista y demás roles, permisos individuales y antecedentes. No modifica operaciones ni asigna responsables históricos.

## API y Flutter

- `GET /api/incidentes`: listado paginado, ordenado por fecha e ID descendentes. Filtros: `estado`, `q`, `tipo`, `envio`, `desde`, `hasta`, `afectado_tipo`, `afectado_id`. `per_page`: 1–50.
- `GET /api/incidentes/{incidente}`: detalle autorizado.
- `GET /api/incidentes/afectados/{tipo}/{afectado}/{incidente}`: detalle que verifica además la pertenencia al padre indicado.
- Se conservan el registro y resolución existentes, mediante reglas compartidas con la web.

El Resource expone identificador, problema, referencia tipificada, responsable, estado, seguimiento y resolución. Las personas se limitan a ID y nombre. Los campos ausentes son `null`; no se serializan modelos de usuario completos ni credenciales. El listado genérico de Flutter muestra referencia, responsable, seguimiento y solución; se verificó su contrato con MockClient, sin afirmar un recorrido móvil de extremo a extremo.

## Verificación realizada

- 16 casos de `IncidenteSeguimientoTest` (159 aserciones): registro y validaciones, permisos, ámbito, referencias incompatibles, responsable, filtros y detalle, cierre y reintentos, fallo de persistencia, rutas anidadas, destinatarios mixtos, coherencia web/API, escape HTML, privacidad de códigos históricos, ausencia de movimientos automáticos, atención con permisos reales de los roles y preservación de permisos ajenos por la migración idempotente.
- Concurrencia real con dos procesos PHP y SQLite aislado: soluciones diferentes producen un cierre y un conflicto; soluciones equivalentes conservan un solo resultado.
- Regresión de propiedad del transportista y dos controles principales de autenticación de rutas web/API.
- Dos pruebas seleccionadas de Flutter, incluido el contrato de consulta de incidencias.
- Revisión en Edge del detalle generado por una prueba aislada, con CSS compilado existente, a 1440 y 390 píxeles. Sin desbordamiento horizontal; formulario y texto largo utilizables.

No se ejecutó toda la batería del repositorio, PHP 8.3/8.4 ni Flutter conectado al backend. No se recompilaron recursos porque no cambian CSS, JavaScript ni dependencias. No se publicaron estos cambios en GitHub.
