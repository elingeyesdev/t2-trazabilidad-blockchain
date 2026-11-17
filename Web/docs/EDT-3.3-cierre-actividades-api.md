# Cierre de actividades (EDT 3.3)

`POST /api/actividades/{actividad}/cerrar`, autenticado con Sanctum, recibe multipart:

- `resultado`: texto obligatorio, máximo 250 caracteres. Se recortan espacios exteriores.
- `evidencia_foto`: imagen real JPEG, PNG o WebP, máximo 5 MB.
- `consumos[i][insumoid]`, `consumos[i][almacenid]`, `consumos[i][cantidad]`.
- Opcional `consumos[i][unidadmedidaid]`: debe coincidir con la unidad del insumo; no hay conversiones.

Las cantidades deben ser positivas, con hasta tres decimales. No se aceptan insumos repetidos. Se mantienen los límites por tipo de actividad (una semilla para siembra y hasta diez insumos para las aplicaciones). Sin `consumos` se recupera el detalle planificado existente; para siembra también puede usarse la semilla y cantidad planificadas del lote. Un arreglo vacío no sustituye un consumo obligatorio. El formulario permite ajustar las cantidades reales.

Solo puede cerrar el operativo asignado autorizado para el lote, respetando secuencia y fase. Responsable y fecha los determina el servidor. Se rechazan campos protegidos como `fechafin`, `usuarioid_ejecutor`, `stock` o `detalle_json`. El resultado se guarda separado de las observaciones de planificación, dentro de `detalle_json.cierre`.

## Respuestas y reintentos

Un cierre confirmado devuelve 200 con el recurso de actividad, incluyendo `resultado`, `consumos`, ejecutor, fecha y URL de fotografía. Los errores de validación devuelven 422 con campos indexados; acceso no autorizado 403; contenido incompatible con un cierre confirmado 409. Un fallo interno devuelve un mensaje genérico sin SQL ni rutas internas.

Se reconoce el mismo cierre por el resultado recortado, SHA-256 de los bytes de la foto, ejecutor y consumos ordenados por identificador, con cantidades normalizadas a tres decimales. `2.5` equivale a `2.500`; cambiar el nombre del archivo no cambia su identidad. Repetir el cierre equivalente recupera el registro y no guarda otro archivo ni movimiento. Los cierres anteriores sin huella no se sobrescriben: devuelven 409. También se autoriza cada reintento.

La fotografía nueva queda en el disco privado `local`. `GET /api/actividades/{actividad}/evidencia` requiere autenticación y acceso al lote/actividad; Flutter debe enviar su token al descargarla. La web usa la ruta autenticada equivalente. Las fotografías públicas anteriores conservan sus URLs existentes.

## Consistencia

Web, API y cierre de siembra comparten `ActividadCierreService`. La transacción bloquea lote, actividad e insumos (estos en orden de identificador). Revalida almacén agrícola autorizado, categoría, unidad y existencias. Registra consumo y movimiento existentes y descuenta una sola vez. Los cambios compartidos de stock usan enteros escalados y actualización condicional sobre el valor persistido para evitar cálculos con flotantes y escrituras perdidas desde modelos desactualizados.

El archivo se guarda antes de confirmar. Un fallo revierte las escrituras y elimina el archivo nuevo; un fallo de limpieza se registra con el disco y ruta pendientes. Los reintentos no guardan una copia permanente; PHP gestiona el archivo temporal de subida. La generación de la respuesta ocurre después de la transacción para que un error de respuesta no elimine una foto confirmada.

## Migración y verificación

La migración `2026_11_15_230000_decimal_stock_consumo_actividades.php` prepara `insumo.stock` y `loteinsumo.cantidadusada` como DECIMAL(18,6). Los movimientos existentes ya tienen tres decimales. En PostgreSQL verifica previamente valores negativos, fuera de rango o con precisión incompatible y se detiene para su revisión; no elimina datos ni los corrige silenciosamente. La reversión conserva la precisión decimal. **No se ejecutó esta migración contra la base actual.** Debe aplicarse antes de desplegar el cierre sobre PostgreSQL.

Verificación dirigida: `php artisan test --compact --filter=ApiCierreActividadTest` (7 pruebas, 73 comprobaciones). Cubre cierre y consulta web/API, acceso a foto, permisos, resultado obligatorio, imagen inválida, cantidades, stock insuficiente, duplicados, campos protegidos, reintentos equivalentes/conflictos, rollback con compensación de archivo y descuento desde modelos desactualizados. Se ejecutó con SQLite aislado; no constituye una prueba de concurrencia real sobre PostgreSQL. No se ejecutó la suite completa ni se modificó una base compartida.
