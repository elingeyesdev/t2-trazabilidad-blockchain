# EDT 3.1 / #24 — Registro de lotes y asignación de actividades

Laravel 12, Sanctum y middleware `action.permission` existentes. Sin migraciones ni dependencias nuevas.

## Decisiones basadas en el modelo existente

- `lote.insumosemillaid` referencia `insumo.insumoid`; no se usa el antiguo error tipográfico `insumosemallaid`.
- La semilla debe ser un material de siembra operativo. Los insumos sin almacén conservan el comportamiento legacy del formulario de lotes; los de almacenes agrícolas se validan con `CampoAccess`, y los demás con el acceso de inventario existente.
- `cultivoid` se obtiene mediante `LoteCultivoResolver`, como en la web.
- `superficie` se expresa en hectáreas, mínimo 0.01. `cantidad_semilla_planificada` usa la unidad de la semilla; el cálculo inicial, stock disponible y redondeo reutilizan la web.
- `ubicacion` es texto de hasta 200 caracteres, normalizado por `UbicacionGpsParser`; las coordenadas son `latitud` (-90 a 90) y `longitud` (-180 a 180). Deben existir ambas o quedar ambas vacías. Se reutiliza la validación terrestre web, incluidas sus condiciones de indisponibilidad del proveedor.
- La asignación es la propia fila `actividad`: `usuarioid` identifica a un único responsable. No existe una tabla paralela de asignaciones. El ámbito agrícola procede de `supervisor_usuarioid` y los helpers de equipo existentes.
- El jefe puede asignarse a sí mismo o elegir un trabajador activo elegible de su equipo. El administrador conserva su papel de supervisión y la matriz de permisos sigue aplicándose.

## Crear lote

`POST /api/lotes`, permiso `lotes.create`, token Bearer Sanctum.

```json
{
  "nombre": "Parcela Norte",
  "insumosemillaid": 12,
  "superficie": 2.75,
  "ubicacion": "Parcela Norte",
  "latitud": -17.7,
  "longitud": -63.1,
  "cantidad_semilla_planificada": 1
}
```

Los identificadores del ejemplo deben reemplazarse por referencias autorizadas reales. Son obligatorios `nombre`, `superficie` e `insumosemillaid`. Los demás campos del ejemplo son opcionales. Se conservan los campos opcionales de planificación y la imagen del formulario web, con sus validaciones existentes.

`usuarioid` se obtiene del usuario autenticado; enviar este campo, incluso null, produce 422. También se rechazan `cultivoid`, `actorid`, `estadolotetipoid`, `unidadsuperficieid`, `codigo_trazabilidad`, fechas administrativas, `imagenurl`, `organizacionid`, `role` y el nombre tipográfico antiguo. Solo los campos validados por el flujo web llegan al modelo.

Respuesta 201: `{ "data": { ... } }` con `LoteConsultaResource`, incluyendo las relaciones de responsable, cultivo, estado y semilla. Se reutiliza el flujo web completo de creación, incluidos historial y siembra inicial cuando corresponde, dentro de una transacción.

## Editar lote

`PATCH /api/lotes/{lote}` o `PUT /api/lotes/{lote}`, permiso `lotes.update` y `LoteAcceso::puedeGestionar` sobre ese lote. Ambos métodos son parciales por compatibilidad con la API existente.

Campos editables: `nombre`, `superficie`, `ubicacion`, `insumosemillaid`, `cantidad_semilla_planificada`, `latitud`, `longitud`. Los campos omitidos permanecen intactos, incluida la relación de cultivo, el código de trazabilidad, actividades y otras relaciones. El responsable se conserva en el servidor. Los lotes cosechados mantienen el bloqueo web.

- `nombre`, `superficie` y `insumosemillaid` no admiten null explícito.
- `ubicacion: null` elimina el texto; `cantidad_semilla_planificada: null` elimina la cantidad explícita, conservando las validaciones web de stock sugerido.
- Las coordenadas admiten null cuando el resultado final deja ambas vacías. Se puede modificar solo una coordenada si la otra ya está guardada.
- Cambiar la semilla vuelve a resolver el cultivo; omitirla conserva el cultivo guardado.

Respuesta 200 mediante el mismo Resource, recargado desde la base de datos. Las consultas GET de EDT 2.1 y los filtros web de EDT 2.3 no cambian.

## Asignar actividad

`POST /api/actividades`, permiso `lotes.update`, jefe agrícola operativo y acceso de gestión al lote.

```json
{
  "loteid": 25,
  "usuarioid": 8,
  "tipoactividadid": 3,
  "prioridadid": 2,
  "descripcion": "Trabajo planificado",
  "fecha_planificada": "2026-12-01",
  "observaciones": "Revisar el sector norte"
}
```

`loteid`, `usuarioid` y `tipoactividadid` son obligatorios. Prioridad, descripción y fecha de inicio usan los valores predeterminados del formulario web si se omiten. `fecha_planificada` y `observaciones` son opcionales.

Se reutilizan las reglas web sobre fase, actividades repetidas y detalle de insumos/riego. Cuando corresponde, enviar `detalle_actividad_json` como una cadena JSON, igual que el formulario web. Por ejemplo, para riego:

```json
{
  "detalle_actividad_json": "{\"riego\":{\"key\":\"goteo\",\"label\":\"Riego por goteo\"}}"
}
```

Para actividades con insumos, la estructura interna es `{"insumos":[{"insumoid":12,"cantidad":1}]}`; el servicio existente verifica tipo, almacén operativo, cantidad y stock. La descripción devuelta puede ser el resumen calculado por la web.

La asignación siempre nace pendiente. No se aceptan `fechafin`, `completar`, `usuarioid_ejecutor`, `orden_secuencia`, `evidencia_foto_path` ni `detalle_json` del cliente. El guardado y la secuencia se ejecutan en una transacción, bloqueando el lote para serializar las asignaciones API. Respuesta 201 con `ActividadConsultaResource` y relaciones permitidas. No se consume stock por asignar una actividad pendiente.

La edición existente de actividades conserva su ruta; la reasignación de `usuarioid` también valida jefe, lote y pertenencia del trabajador. No se permite trasladar una actividad a otro lote. La respuesta se recarga con el Resource de consulta.

## Errores para Flutter

Las rutas de lotes y actividades devuelven JSON incluso si el cliente omite `Accept: application/json`. Se recomienda enviar esa cabecera y `Content-Type: application/json`.

- 401: falta autenticación.
- 403: falta permiso o acceso al lote/actividad, siguiendo la escritura existente.
- 404: registro inexistente; las consultas mantienen el filtrado de registros invisibles.
- 422: validación por campo, incluidas referencias no elegibles dentro del ámbito.

```json
{
  "message": "Seleccione un trabajador activo de su equipo.",
  "errors": {
    "usuarioid": ["Seleccione un trabajador activo de su equipo."]
  }
}
```

Flutter debe leer `errors` como un mapa de nombre exacto del campo a lista de mensajes. Los errores de detalle se asocian a `detalle_actividad_json`; incompatibilidad de fase a `tipoactividadid`; bloqueo de edición de un lote cerrado a `loteid`. No es necesario interpretar `message` para asociar errores a controles.

## Validación

Pruebas de escritura: `tests/Feature/ApiRegistroLotesAsignacionesTest.php`. Usan SQLite en memoria y `RefreshDatabase`, con validación geográfica simulada; no modifican la base compartida ni realizan llamadas geográficas externas.

Regresión pertinente:

```powershell
php artisan test --compact --filter='ApiRegistroLotesAsignacionesTest|ApiCampoOwnershipAislamientoTest|ApiConsultaLotesActividadesTest|LotesListadoFiltrosTest|ActividadLotePermisosTest|AgriculturaOwnershipAislamientoTest|LotesAccessTest|CampoJefeScopeTest'
```

Las pruebas comprueban valores y relaciones persistidos, visibilidad en listado/detalle web, asignaciones web, errores por campo, aislamiento, autenticación, permisos, actualizaciones parciales, null, restricciones de fase, actividades repetidas y rollback ante fallos de historial/secuencia.

Limitaciones: no se realizó un recorrido manual en navegador porque el host de acceso al navegador no está disponible. La coherencia web se comprobó con peticiones HTTP de prueba que renderizan las vistas reales. No se ejecutaron migraciones en PostgreSQL ni pruebas con un dispositivo Flutter; tampoco se verificó el proveedor geográfico externo en vivo.