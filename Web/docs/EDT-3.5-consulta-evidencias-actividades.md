# EDT 3.5 — Consulta de fotografías e insumos (#28)

## Origen y alcance

Se reutilizan los detalles existentes: `GET /api/actividades/{actividad}`, `GET /api/lotes/{lote}/actividades/{actividad}` y `GET /actividades/{actividad}`. El detalle web ahora muestra la actividad seleccionada con el layout Tabler verde existente; los listados y el historial enlazan a ese detalle. La consulta es de solo lectura y no ejecuta servicios de cierre ni de stock.

El esquema admite **una fotografía por actividad**, indicada por `actividad.evidencia_foto_path`. No existe colección de evidencias ni joins que multipliquen consumos. La foto de otra tarea, la imagen del lote o una imagen del catálogo no se usan como evidencia de la actividad seleccionada.

El cierre EDT 3.3 persiste el resultado, la cantidad y la unidad histórica en `detalle_json`, además de ejecutor y fecha en `usuarioid_ejecutor`/`fechafin`. Solo se leen filas de detalle marcadas `stock_aplicado`, y únicamente cuando la actividad está cerrada. Una planificación pendiente nunca se presenta como consumo efectivo.

Para registros anteriores sin ese detalle se usa la relación `actividad → loteinsumo` por `actividadid`, comprobando también `loteid`. Los consumos del lote sin actividad identificable quedan excluidos. Esa tabla no guarda unidad ni almacén históricos: se muestra la unidad del catálogo con `unidad_historica: false`, y almacén `null`. No se infiere el almacén desde la ubicación actual del insumo ni se inventa un responsable histórico cuando no existe ejecutor. Los snapshots conservan sus nombres, unidades y almacén guardados aunque cambie el catálogo.

## Contrato API

Se conservan `actividadid`, estado, `pendiente`, `completada`, `fechafin`, `responsable`, `usuario` y `ejecutor`. `responsable`/`usuario` siguen indicando el trabajador asignado. `responsable_cierre` identifica al ejecutor del cierre; es `null` para pendientes o cuando no quedó registrado. Las fechas conservan la serialización ISO 8601 UTC de los Resources existentes. La web conserva el formato de fecha de la aplicación.

Campos de consulta:

- `resultado`: texto persistido, o `null`.
- `consumos`: lista de `insumoid`, `nombre`, `cantidad`, `unidadmedidaid`, `unidad`, `unidad_historica`, `almacenid`.
- `cantidad`: **cadena decimal**, sin conversión a float. Los cierres EDT 3.3 conservan tres decimales (ejemplo `"2.500"`); el fallback de registros antiguos conserva seis (`"2.500000"`). No se recalcula desde el stock.
- `evidencia_estado`: `sin_fotografia`, `disponible` o `no_disponible`.
- `tiene_evidencia`: indica que hay una fotografía registrada en una actividad cerrada; sigue siendo `true` si falta el archivo.
- `evidencia_foto_url`: ruta autenticada absoluta si el archivo está disponible; de lo contrario `null`.

Por protección, la clave heredada `evidencia_foto_path` permanece en el contrato pero devuelve `null`: **los clientes deben usar `evidencia_foto_url`**, no construir `/storage/...`. El Flutter actual no consume ese campo de ruta. No se exponen rutas físicas ni la huella de cierre. Los endpoints de lectura cargan anticipadamente consumos/unidades y las relaciones existentes para evitar N+1 de consultas SQL.

## Descarga y privacidad

`GET /api/actividades/{actividad}/evidencia` requiere `Authorization: Bearer <token>` y permisos de lectura de lotes, actividad y ámbito. Flutter puede usar la URL recibida con `Image.network(url, headers: {'Authorization': 'Bearer $token', 'Accept': 'image/*'})`, enviando el token solo al mismo servidor de confianza de su API. Para ampliar se debe descargar con esos mismos encabezados; abrir la URL en un navegador externo no transmite el token.

No hay vencimiento de URL temporal; cada petición vuelve a autorizarse. La web usa sesión y `GET /actividades/{actividad}/evidencia`. La respuesta lleva `Cache-Control: private, no-store` y `nosniff`. Ausencia de archivo, actividad inexistente o evidencia de otra actividad devuelve 404; el detalle API usa 404 para registros fuera de alcance y el detalle web conserva su 403. La ruta anidada comprueba pertenencia al lote.

Las URLs se construyen desde el host de la petición (con proxies confiables configurados en el proyecto). Flutter debe llamar al dominio HTTPS o IP accesible de su API, no a `localhost` de otro equipo. No se introdujo un dominio fijo ni cambios de credenciales.

Las fotos antiguas de `actividades_evidencia` se leen desde su disco existente por el controlador autorizado. **Se bloquea el acceso público directo** en `public/.htaccess`, `nginx.conf` y el router `server.php` usado por `artisan serve`. No se movieron archivos ni se modificaron filas al consultar. En despliegues Nginx debe aplicarse y recargarse la configuración del repositorio; un servidor/CDN externo que publique directamente ese prefijo debe bloquearlo igualmente y retirar sus copias públicas previas. Los enlaces públicos anteriores dejan de funcionar por este cambio intencional de privacidad. Las fotos privadas EDT 3.3 permanecen privadas.

## Verificación

Resultado: **14 pruebas aprobadas, 197 comprobaciones**. Pruebas dirigidas en SQLite aislado: `php artisan test --compact --filter='ApiConsultaEvidenciaActividadTest|ApiCierreActividadTest'`. Incluyen valores concretos y exclusión de datos de otra actividad/ámbito, foto y cantidades históricas, unidad de catálogo modificada, responsable/fecha, estados ausentes y archivo perdido, autorizaciones y rutas anidadas, consultas repetidas sin cambios, y regresión del cierre. Los casos de múltiples fotografías no aplican al esquema de una foto por actividad. Se comprueban además plantillas Blade y sintaxis PHP; no hay cambios en bundles que requieran compilación Vite.

La prohibición de URLs públicas se verificó por HTTP con el router de desarrollo (403). Apache/Nginx y una CDN no se ejecutaron en esta revisión; se debe aplicar su configuración al desplegar. No se realizó inspección visual en navegador a tamaños de escritorio/móvil. No hay migraciones, paquetes nuevos ni cambios en la lógica de inventario.
